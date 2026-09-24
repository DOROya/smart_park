// Server-side port of the driver app's package pricing
// (driver_vehicle_selection_page.dart + driver_package_selection_page.dart).
// The server recomputes every checkout amount from the establishment's own
// rates, so a modified app cannot choose its own price.

const PLATFORM_FEE_RATE = 0.05;

const SUPPORTED_PAYMENT_METHODS = ["card", "gcash", "paymaya", "qrph"];

const MAX_DURATION = { extended: 12, daily: 7 };

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Mirrors `_parseAmount`: numbers as-is, else the first number in a string. */
function parseAmount(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value !== "string") return 0;
  const match = value.trim().match(/([0-9]+(?:\.[0-9]+)?)/);
  return match ? parseFloat(match[1]) : 0;
}

/** Rates a vehicle type offers, read the same way the app's picker does. */
function vehicleRates(ratesByType, vehicleType) {
  const vehicleRate = isPlainObject(ratesByType)
    ? ratesByType[vehicleType]
    : undefined;
  const rateMap = isPlainObject(vehicleRate) ? vehicleRate : {};
  return {
    initial: parseAmount(
      rateMap.initial ?? rateMap.hourly ?? rateMap.rates ?? vehicleRate,
    ),
    succeedingHour: parseAmount(
      rateMap.succeedingHour ?? rateMap.succeeding_hour,
    ),
    succeedingDaily: parseAmount(
      rateMap.succeedingDaily ?? rateMap.succeeding_daily ?? rateMap.daily,
    ),
  };
}

/**
 * Total price in pesos for a plan, or throws if the plan is not offered or
 * the duration is out of range. Base is a single fixed stay (duration 1).
 */
function computeAmount({ ratesByType, vehicleType, plan, duration }) {
  const rates = vehicleRates(ratesByType, vehicleType);
  const days = Number.isInteger(duration) ? duration : NaN;

  switch (plan) {
    case "base":
      if (rates.initial <= 0) throw new PricingError("Base package is not offered.");
      return { amount: rates.initial, duration: 1 };
    case "extended":
      if (rates.initial <= 0 || rates.succeedingHour <= 0) {
        throw new PricingError("Extended stay is not offered.");
      }
      if (!(days >= 1 && days <= MAX_DURATION.extended)) {
        throw new PricingError("Invalid number of additional hours.");
      }
      return {
        amount: rates.initial + rates.succeedingHour * days,
        duration: days,
      };
    case "daily":
      if (rates.succeedingDaily <= 0) {
        throw new PricingError("Daily package is not offered.");
      }
      if (!(days >= 1 && days <= MAX_DURATION.daily)) {
        throw new PricingError("Invalid number of days.");
      }
      return { amount: rates.succeedingDaily * days, duration: days };
    default:
      throw new PricingError("Unknown package.");
  }
}

class PricingError extends Error {}

/** Same rounding as the app's `platformFeeCentavosFor`. */
function platformFeeCentavosFor(grossCentavos) {
  return Math.round(grossCentavos * PLATFORM_FEE_RATE);
}

/** Same estimate as the app's `estimateProcessorFeeCentavos`. */
function estimateProcessorFeeCentavos(grossCentavos, paymentMethod) {
  const rate =
    paymentMethod === "card"
      ? 0.035
      : paymentMethod === "gcash" || paymentMethod === "paymaya"
        ? 0.02
        : paymentMethod === "qrph"
          ? 0.0134
          : 0.02;
  return Math.round(grossCentavos * rate);
}

module.exports = {
  PLATFORM_FEE_RATE,
  SUPPORTED_PAYMENT_METHODS,
  PricingError,
  parseAmount,
  vehicleRates,
  computeAmount,
  platformFeeCentavosFor,
  estimateProcessorFeeCentavos,
};
