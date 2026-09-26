// Verification and password-reset emails. Firebase's built-in sender is
// locked to noreply@<project>.firebaseapp.com with a fixed template (and
// lands in spam), so the links are generated with the Admin SDK and sent
// from our own Gmail account instead. The links still go through Firebase's
// action handler, so emailVerified and password resets work as before.

const crypto = require("node:crypto");
const nodemailer = require("nodemailer");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const SENDER_ADDRESS = "smartpark.noreply@gmail.com";
const SENDER_NAME = "SmartPark";
const THROTTLE = "mail_throttle";
const COOLDOWN_MS = 60 * 1000;
const WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_WINDOW = 5;

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** Sign-up stores names as "First|Last"; greet by first name only. */
function firstNameFrom(displayName) {
  const name = String(displayName || "").split("|")[0].trim().split(/\s+/)[0];
  return name || "there";
}

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function layout({ heading, intro, buttonLabel, link, outro }) {
  const safeLink = escapeHtml(link);
  const html = `<!doctype html>
<html>
<body style="margin:0;padding:0;background:#f4f5f7;font-family:Arial,Helvetica,sans-serif;color:#1f2933;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:12px;overflow:hidden;">
        <tr><td style="background:#1f2933;padding:20px 28px;color:#f2c94c;font-size:22px;font-weight:bold;">SmartPark</td></tr>
        <tr><td style="padding:28px;">
          <h1 style="margin:0 0 16px;font-size:20px;color:#1f2933;">${escapeHtml(heading)}</h1>
          <p style="margin:0 0 24px;font-size:15px;line-height:1.5;">${escapeHtml(intro)}</p>
          <p style="margin:0 0 24px;"><a href="${safeLink}" style="display:inline-block;background:#f2c94c;color:#1f2933;text-decoration:none;font-weight:bold;padding:12px 24px;border-radius:8px;">${escapeHtml(buttonLabel)}</a></p>
          <p style="margin:0 0 8px;font-size:13px;color:#52606d;">If the button doesn't work, copy this link into your browser:</p>
          <p style="margin:0 0 24px;font-size:12px;word-break:break-all;"><a href="${safeLink}" style="color:#3b6fd4;">${safeLink}</a></p>
          <p style="margin:0;font-size:13px;color:#52606d;">${escapeHtml(outro)}</p>
        </td></tr>
        <tr><td style="padding:16px 28px;background:#f9fafb;font-size:12px;color:#9aa5b1;">&mdash; The SmartPark Team</td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
  const text = `${heading}\n\n${intro}\n\n${buttonLabel}: ${link}\n\n${outro}\n\n- The SmartPark Team`;
  return { html, text };
}

function buildVerificationEmail({ displayName, link }) {
  return {
    subject: "Confirm your SmartPark account",
    ...layout({
      heading: `Hi ${firstNameFrom(displayName)}, welcome to SmartPark!`,
      intro: "Please confirm your email address to finish setting up your account.",
      buttonLabel: "Confirm my email",
      link,
      outro: "If you didn't create a SmartPark account, you can safely ignore this email.",
    }),
  };
}

function buildPasswordResetEmail({ displayName, link }) {
  return {
    subject: "Reset your SmartPark password",
    ...layout({
      heading: `Hi ${firstNameFrom(displayName)},`,
      intro: "We received a request to reset your SmartPark password. The link below expires in one hour.",
      buttonLabel: "Reset my password",
      link,
      outro: "If you didn't ask to reset your password, you can ignore this email. Your password won't change.",
    }),
  };
}

/**
 * Pure throttle rule: one send per COOLDOWN_MS and MAX_PER_WINDOW per
 * WINDOW_MS. Returns the pruned send times plus how long to wait (0 = ok).
 */
function throttleDecision(sentAtMs, nowMs) {
  const recent = (sentAtMs || []).filter((t) => nowMs - t < WINDOW_MS).sort((a, b) => a - b);
  if (recent.length === 0) return { recent, waitMs: 0 };
  let waitMs = COOLDOWN_MS - (nowMs - recent[recent.length - 1]);
  if (recent.length >= MAX_PER_WINDOW) {
    waitMs = Math.max(waitMs, WINDOW_MS - (nowMs - recent[0]));
  }
  return { recent, waitMs: Math.max(0, waitMs) };
}

/** Records a send, or throws resource-exhausted if this email is throttled. */
async function claimSendSlot(action, email) {
  const db = getFirestore();
  const id = crypto.createHash("sha256").update(`${action}:${email}`).digest("hex");
  const ref = db.collection(THROTTLE).doc(id);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const sentAtMs = (snap.data()?.sentAt || []).map((t) => t.toMillis());
    const now = Date.now();
    const { recent, waitMs } = throttleDecision(sentAtMs, now);
    if (waitMs > 0) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many emails were requested. Please wait a few minutes and try again.",
        { retryAfterSeconds: Math.ceil(waitMs / 1000) },
      );
    }
    tx.set(ref, {
      action,
      sentAt: [...recent, now].map((t) => Timestamp.fromMillis(t)),
      expiresAt: Timestamp.fromMillis(now + WINDOW_MS),
    });
  });
}

async function sendMail(appPassword, to, message) {
  const transport = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 587,
    secure: false,
    requireTLS: true,
    // Secrets set from a Windows terminal can carry a trailing "\r\n".
    auth: { user: SENDER_ADDRESS, pass: String(appPassword).trim() },
  });
  try {
    await transport.sendMail({
      from: { name: SENDER_NAME, address: SENDER_ADDRESS },
      to,
      subject: message.subject,
      text: message.text,
      html: message.html,
    });
  } catch (error) {
    logger.error("Sending email failed", { code: error.code, response: error.response });
    throw new HttpsError("unavailable", "Unable to send the email right now. Please try again.");
  }
}

/** Callable: emails the signed-in user a link to verify their address. */
async function sendVerificationEmail(request, appPassword) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Please sign in again.");
  const user = await getAuth().getUser(request.auth.uid);
  const email = normalizeEmail(user.email);
  if (!email) throw new HttpsError("failed-precondition", "This account has no email address.");
  if (user.emailVerified) return { alreadyVerified: true };

  await claimSendSlot("verify", email);
  const link = await getAuth().generateEmailVerificationLink(email);
  await sendMail(appPassword, email, buildVerificationEmail({ displayName: user.displayName, link }));
  return { alreadyVerified: false };
}

/**
 * Callable (no sign-in needed): emails a password-reset link. Unknown
 * addresses get the same response, so this can't be used to probe which
 * emails have accounts.
 */
async function sendPasswordResetEmail(request, appPassword) {
  const email = normalizeEmail(request.data?.email);
  if (!email || !email.includes("@") || email.length > 254) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }

  await claimSendSlot("password-reset", email);
  let user;
  try {
    user = await getAuth().getUserByEmail(email);
  } catch (error) {
    if (error.code === "auth/user-not-found") return { sent: true };
    throw error;
  }
  const link = await getAuth().generatePasswordResetLink(email);
  await sendMail(appPassword, email, buildPasswordResetEmail({ displayName: user.displayName, link }));
  return { sent: true };
}

module.exports = {
  escapeHtml,
  firstNameFrom,
  buildVerificationEmail,
  buildPasswordResetEmail,
  throttleDecision,
  sendVerificationEmail,
  sendPasswordResetEmail,
};
