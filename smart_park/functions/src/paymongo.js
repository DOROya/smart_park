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

/** Mirrors the app's old `PayMongoCheckoutLink.isPaid`. */
function isSessionPaid(session) {
  const attributes = session?.attributes || {};
  if (String(attributes.status || "").toLowerCase() === "paid") return true;
  const payments = Array.isArray(attributes.payments) ? attributes.payments : [];
  return payments.some(
    (p) => String(p?.attributes?.status || "").toLowerCase() === "paid",
  );
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

module.exports = {
  buildCheckoutPayload,
  createCheckoutSession,
  getCheckoutSession,
  isSessionPaid,
  paidPaymentMethod,
};
