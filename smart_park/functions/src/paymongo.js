// Minimal PayMongo client. The secret key only ever lives on the server
// (Secret Manager via defineSecret) and is passed in per call.

const { SUPPORTED_PAYMENT_METHODS } = require("./pricing");

const BASE_URL = "https://api.paymongo.com/v1";

function authHeader(secretKey) {
  return "Basic " + Buffer.from(`${secretKey.trim()}:`).toString("base64");
}

async function request(secretKey, method, path, body) {
  const response = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      authorization: authHeader(secretKey),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const decoded = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail = decoded?.errors?.[0]?.detail;
    throw new Error(
      `PayMongo ${method} ${path} failed (${response.status})` +
        (detail ? `: ${detail}` : ""),
    );
  }
  return decoded;
}

/** Same body the app used to build in `buildSplitPaymentCheckoutPayload`. */
function buildCheckoutPayload({
  amountCentavos,
  platformFeeCentavos,
  description,
  remarks,
  destinationAccountId,
  paymentMethod,
  metadata,
  billing,
}) {
  const methods = SUPPORTED_PAYMENT_METHODS.includes(paymentMethod)
    ? [paymentMethod]
    : SUPPORTED_PAYMENT_METHODS;
  return {
    data: {
      attributes: {
        description,
        currency: "PHP",
        line_items: [
          {
            amount: amountCentavos,
            currency: "PHP",
            description: remarks || description,
            name: description,
            quantity: 1,
          },
        ],
        payment_method_types: methods,
        // Pre-fills the payer's details so the driver only confirms at the
        // gate. Left out unless both are known.
        ...(billing?.name && billing?.email
          ? { billing: { name: billing.name, email: billing.email } }
          : {}),
        show_line_items: true,
        success_url: "https://smartpark.app/payment-success",
        cancel_url: "https://smartpark.app/payment-cancel",
        platform_fee: platformFeeCentavos,
        destination_account: destinationAccountId,
        metadata: {
          ...metadata,
          platform_fee: platformFeeCentavos,
          destination_account: destinationAccountId,
        },
      },
    },
  };
}

async function createCheckoutSession(secretKey, payload) {
  const decoded = await request(secretKey, "POST", "/checkout_sessions", payload);
  const data = decoded.data || {};
  const attributes = data.attributes || {};
  if (!data.id || !attributes.checkout_url) {
    throw new Error("PayMongo response is missing the checkout session.");
  }
  return {
    id: data.id,
    checkoutUrl: attributes.checkout_url,
    referenceNumber: attributes.reference_number || "",
    status: attributes.status || "unknown",
  };
}

async function getCheckoutSession(secretKey, sessionId) {
  const decoded = await request(
    secretKey,
    "GET",
    `/checkout_sessions/${encodeURIComponent(sessionId)}`,
  );
  return decoded.data || {};
}

/** Stops a checkout session from accepting payment. Fails if already paid. */
async function expireCheckoutSession(secretKey, sessionId) {
  await request(
    secretKey,
    "POST",
    `/checkout_sessions/${encodeURIComponent(sessionId)}/expire`,
  );
}

/** Mirrors the app's old `PayMongoCheckoutLink.isPaid`. */
function isSessionPaid(session) {
  const attributes = session?.attributes || {};
  if (String(attributes.status || "").toLowerCase() === "paid") return true;
  const payments = Array.isArray(attributes.payments) ? attributes.payments : [];
  return payments.some(
    (p) => String(p?.attributes?.status || "").toLowerCase() === "paid",
  );
}

/** Id of the payment that settled a checkout session, if any. */
function paidPaymentId(session) {
  const payments = session?.attributes?.payments;
  if (!Array.isArray(payments)) return null;
  const paid = payments.find(
    (p) => String(p?.attributes?.status || "").toLowerCase() === "paid",
  );
  return paid?.id || null;
}

/** Refunds part (or all) of a payment. Returns { id, status }. */
async function createRefund(secretKey, { paymentId, amountCentavos, notes, metadata }) {
  const decoded = await request(secretKey, "POST", "/refunds", {
    data: {
      attributes: {
        amount: amountCentavos,
        payment_id: paymentId,
        // "others" is the one reason both PayMongo's guide and reference list.
        reason: "others",
        notes: notes ? String(notes).slice(0, 255) : undefined,
        metadata,
      },
    },
  });
  const data = decoded.data || {};
  if (!data.id) throw new Error("PayMongo response is missing the refund.");
  return { id: data.id, status: data.attributes?.status || "pending" };
}

/** A refund's current state at PayMongo. Returns { id, status }. */
async function getRefund(secretKey, refundId) {
  const decoded = await request(secretKey, "GET", `/refunds/${encodeURIComponent(refundId)}`);
  const data = decoded.data || {};
  return { id: data.id || refundId, status: data.attributes?.status || "pending" };
}

/** Payment method PayMongo actually charged, if it reports one. */
function paidPaymentMethod(session) {
  const payments = session?.attributes?.payments;
  if (!Array.isArray(payments)) return null;
  const paid = payments.find(
    (p) => String(p?.attributes?.status || "").toLowerCase() === "paid",
  );
  return paid?.attributes?.source?.type || null;
}

// ---- Direct payments (Payment Intents) --------------------------------------
// Used when the driver saved their payment details with the temporary QR: at
// the gate the server attaches them, so the driver only approves the payment
// in their wallet (or the bank's OTP for a card) instead of filling in
// PayMongo's checkout form.

/** PayMongo metadata is flat strings. */
function flatMetadata(metadata) {
  const out = {};
  for (const [key, value] of Object.entries(metadata || {})) {
    if (value === undefined || value === null) continue;
    out[key] = String(value);
  }
  return out;
}

/** Same charge as the checkout payload, for one payment method type. */
function buildPaymentIntentPayload({
  amountCentavos,
  platformFeeCentavos,
  description,
  destinationAccountId,
  paymentMethod,
  metadata,
}) {
  return {
    data: {
      attributes: {
        amount: amountCentavos,
        currency: "PHP",
        payment_method_allowed: [paymentMethod],
        capture_type: "automatic",
        description,
        statement_descriptor: "SmartPark",
        metadata: flatMetadata({
          ...metadata,
          platform_fee: platformFeeCentavos,
          destination_account: destinationAccountId,
        }),
      },
    },
  };
}

function intentSummary(data) {
  const attributes = data?.attributes || {};
  return {
    id: data?.id || "",
    status: String(attributes.status || "unknown"),
    redirectUrl: attributes.next_action?.redirect?.url || "",
  };
}

async function createPaymentIntent(secretKey, payload) {
  const decoded = await request(secretKey, "POST", "/payment_intents", payload);
  if (!decoded.data?.id) throw new Error("PayMongo response is missing the payment intent.");
  return intentSummary(decoded.data);
}

async function getPaymentIntent(secretKey, intentId) {
  const decoded = await request(
    secretKey,
    "GET",
    `/payment_intents/${encodeURIComponent(intentId)}`,
  );
  return decoded.data || {};
}

/** Releases an unfinished intent. Fails if it is already paid or processing. */
async function cancelPaymentIntent(secretKey, intentId) {
  await request(secretKey, "POST", `/payment_intents/${encodeURIComponent(intentId)}/cancel`);
}

/** An e-wallet payment method from the driver's saved details. */
async function createPaymentMethod(secretKey, { type, billing }) {
  const decoded = await request(secretKey, "POST", "/payment_methods", {
    data: { attributes: { type, ...(billing ? { billing } : {}) } },
  });
  if (!decoded.data?.id) throw new Error("PayMongo response is missing the payment method.");
  return decoded.data.id;
}

/** A payment method the app made (a saved card), to check it is real. */
async function getPaymentMethod(secretKey, methodId) {
  const decoded = await request(
    secretKey,
    "GET",
    `/payment_methods/${encodeURIComponent(methodId)}`,
  );
  return decoded.data || {};
}

/**
 * Attaches [paymentMethodId] to the intent. Returns { id, status,
 * redirectUrl }: "succeeded" is paid; "awaiting_next_action" has the
 * wallet's (or the bank's 3-D Secure) page in redirectUrl.
 */
async function attachPaymentIntent(secretKey, intentId, { paymentMethodId, returnUrl }) {
  const decoded = await request(
    secretKey,
    "POST",
    `/payment_intents/${encodeURIComponent(intentId)}/attach`,
    { data: { attributes: { payment_method: paymentMethodId, return_url: returnUrl } } },
  );
  return intentSummary(decoded.data);
}

function isIntentPaid(intent) {
  const attributes = intent?.attributes || {};
  if (String(attributes.status || "").toLowerCase() === "succeeded") return true;
  const payments = Array.isArray(attributes.payments) ? attributes.payments : [];
  return payments.some((p) => String(p?.attributes?.status || "").toLowerCase() === "paid");
}

module.exports = {
  buildCheckoutPayload,
  createCheckoutSession,
  getCheckoutSession,
  expireCheckoutSession,
  isSessionPaid,
  paidPaymentId,
  createRefund,
  getRefund,
  paidPaymentMethod,
  flatMetadata,
  buildPaymentIntentPayload,
  createPaymentIntent,
  getPaymentIntent,
  cancelPaymentIntent,
  createPaymentMethod,
  getPaymentMethod,
  attachPaymentIntent,
  isIntentPaid,
};
