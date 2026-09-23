#!/usr/bin/env node

/*
 * Migration: Split old combined `establishments` documents into:
 * - `establishments/{establishmentId}` (base fields)
 * - `establishment_details/{establishmentId}` (extended fields)
 *
 * Auth source:
 * - Reuses Firebase CLI cached OAuth access token from configstore.
 *
 * Usage:
 *   node scripts/migrate_establishments_split.js --project smartpark-87e3d --dry-run
 *   node scripts/migrate_establishments_split.js --project smartpark-87e3d --apply
 */

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const FIRESTORE_BASE_URL = 'https://firestore.googleapis.com/v1';
const EXAMPLE_DEFAULTS = {
  policies: 'Rules.',
  rates: {
    car: '100',
    motorcycle: '30',
  },
  slots: {
    car: 10,
    motorcycle: 5,
  },
  pricing: 'Car: 100, Motorcycle: 30',
  status: 'approved',
  reviewedAt: '2026-06-29T15:52:15.000Z',
  reviewedBy: 'GWBK5QsdMNMHdPDjiPgrd7g3u3C2',
};

function parseArgs(argv) {
  const args = {
    project: 'smartpark-87e3d',
    dryRun: false,
    apply: false,
    resetLiveSlots: false,
    pageSize: 200,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--project' && argv[i + 1]) {
      args.project = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === '--page-size' && argv[i + 1]) {
      const parsed = Number(argv[i + 1]);
      if (!Number.isNaN(parsed) && parsed > 0) {
        args.pageSize = parsed;
      }
      i += 1;
      continue;
    }
    if (token === '--dry-run') {
      args.dryRun = true;
      continue;
    }
    if (token === '--apply') {
      args.apply = true;
      continue;
    }
    if (token === '--reset-live-slots') {
      args.resetLiveSlots = true;
      continue;
    }
  }

  if (!args.dryRun && !args.apply) {
    args.dryRun = true;
  }

  return args;
}

function getFirebaseToolsConfigPath() {
  if (process.platform === 'win32') {
    const appData = process.env.APPDATA;
    const candidates = [];
    if (appData) {
      candidates.push(path.join(appData, 'configstore', 'firebase-tools.json'));
    }
    if (process.env.USERPROFILE) {
      candidates.push(
        path.join(
          process.env.USERPROFILE,
          '.config',
          'configstore',
          'firebase-tools.json',
        ),
      );
      candidates.push(
        path.join(
          process.env.USERPROFILE,
          'AppData',
          'Roaming',
          'configstore',
          'firebase-tools.json',
        ),
      );
    }

    for (const candidate of candidates) {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }

    throw new Error(
      `Cannot find firebase-tools config in known Windows paths: ${candidates.join(', ')}`,
    );
  }

  const xdg = process.env.XDG_CONFIG_HOME;
  if (xdg) {
    return path.join(xdg, 'configstore', 'firebase-tools.json');
  }
  return path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
}

function getAccessTokenFromFirebaseTools() {
  const filePath = getFirebaseToolsConfigPath();
  if (!fs.existsSync(filePath)) {
    throw new Error(`firebase-tools config not found at ${filePath}`);
  }

  const raw = fs.readFileSync(filePath, 'utf8');
  const parsed = JSON.parse(raw);
  const accessToken = parsed?.tokens?.access_token;
  const expiresAt = parsed?.tokens?.expires_at;

  if (!accessToken) {
    throw new Error('No OAuth access token found in firebase-tools config.');
  }

  if (typeof expiresAt === 'number' && Date.now() > expiresAt) {
    throw new Error(
      'Firebase CLI access token is expired. Run `firebase login --reauth` then retry.',
    );
  }

  return accessToken;
}

function toRestValue(value) {
  if (value === null || value === undefined) {
    return { nullValue: null };
  }

  if (value instanceof Date) {
    return { timestampValue: value.toISOString() };
  }

  const valueType = typeof value;
  if (valueType === 'string') {
    return { stringValue: value };
  }
  if (valueType === 'boolean') {
    return { booleanValue: value };
  }
  if (valueType === 'number') {
    if (Number.isInteger(value)) {
      return { integerValue: String(value) };
    }
    return { doubleValue: value };
  }

  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map((item) => toRestValue(item)),
      },
    };
  }

  if (valueType === 'object') {
    if (
      Object.prototype.hasOwnProperty.call(value, 'latitude') &&
      Object.prototype.hasOwnProperty.call(value, 'longitude') &&
      Object.keys(value).length <= 2
    ) {
      return {
        geoPointValue: {
          latitude: Number(value.latitude),
          longitude: Number(value.longitude),
        },
      };
    }

    const fields = {};
    for (const [k, v] of Object.entries(value)) {
      fields[k] = toRestValue(v);
    }
    return { mapValue: { fields } };
  }

  return { stringValue: String(value) };
}

function fromRestValue(value) {
  if (!value || typeof value !== 'object') {
    return null;
  }
  if (Object.prototype.hasOwnProperty.call(value, 'nullValue')) {
    return null;
  }
  if (Object.prototype.hasOwnProperty.call(value, 'stringValue')) {
    return value.stringValue;
  }
  if (Object.prototype.hasOwnProperty.call(value, 'booleanValue')) {
    return Boolean(value.booleanValue);
  }
  if (Object.prototype.hasOwnProperty.call(value, 'integerValue')) {
    return Number(value.integerValue);
  }
  if (Object.prototype.hasOwnProperty.call(value, 'doubleValue')) {
    return Number(value.doubleValue);
  }
  if (Object.prototype.hasOwnProperty.call(value, 'timestampValue')) {
    return value.timestampValue;
  }
  if (Object.prototype.hasOwnProperty.call(value, 'geoPointValue')) {
    return {
      latitude: Number(value.geoPointValue.latitude),
      longitude: Number(value.geoPointValue.longitude),
    };
  }
  if (Object.prototype.hasOwnProperty.call(value, 'arrayValue')) {
    const arr = value.arrayValue.values || [];
    return arr.map((v) => fromRestValue(v));
  }
  if (Object.prototype.hasOwnProperty.call(value, 'mapValue')) {
    const fields = value.mapValue.fields || {};
    const obj = {};
    for (const [k, v] of Object.entries(fields)) {
      obj[k] = fromRestValue(v);
    }
    return obj;
  }
  return null;
}

function docFromRest(restDoc) {
  const obj = {};
  const fields = restDoc.fields || {};
  for (const [k, v] of Object.entries(fields)) {
    obj[k] = fromRestValue(v);
  }
  return obj;
}

function documentName(projectId, collection, docId) {
  return `projects/${projectId}/databases/(default)/documents/${collection}/${docId}`;
}

function ensureNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function ensureString(value, fallback = '') {
  const text = typeof value === 'string' ? value.trim() : '';
  return text || fallback;
}

function normalizeSlotMap(input) {
  const src = input && typeof input === 'object' ? input : {};
  const car = Math.max(
    0,
    Math.trunc(ensureNumber(src.car, EXAMPLE_DEFAULTS.slots.car)),
  );
  const motorcycle = Math.max(
    0,
    Math.trunc(
      ensureNumber(
        src.motorcycle,
        EXAMPLE_DEFAULTS.slots.motorcycle,
      ),
    ),
  );
  return {
    car,
    motorcycle,
  };
}

function normalizeVehicleRate(input, defaultInitial, defaultSuccHour = '', defaultSuccDaily = '') {
  if (input && typeof input === 'object') {
    return {
      initial: ensureString(input.initial || input.rates || input.hourly, defaultInitial),
      succeedingHour: ensureString(input.succeedingHour || input.succeeding_hour, defaultSuccHour),
      succeedingDaily: ensureString(input.succeedingDaily || input.succeeding_daily || input.daily, defaultSuccDaily),
    };
  }
  const strVal = ensureString(input, defaultInitial);
  return {
    initial: strVal,
    succeedingHour: defaultSuccHour,
    succeedingDaily: defaultSuccDaily,
  };
}

function normalizeRates(input) {
  const src = input && typeof input === 'object' ? input : {};
  return {
    car: normalizeVehicleRate(src.car, '100', '20', '250'),
    motorcycle: normalizeVehicleRate(
      src.motorcycle,
      '30',
      '10',
      '100',
    ),
  };
}

function formatRateSummaryVal(rateObj) {
  if (rateObj && typeof rateObj === 'object') {
    const init = rateObj.initial || '-';
    const succH = rateObj.succeedingHour ? ` (+${rateObj.succeedingHour}/hr)` : '';
    const succD = rateObj.succeedingDaily ? ` (${rateObj.succeedingDaily}/day)` : '';
    return `${init}${succH}${succD}`;
  }
  return rateObj || '-';
}

function buildPricingSummary(rates) {
  return `Car: ${formatRateSummaryVal(rates.car)}, Motorcycle: ${formatRateSummaryVal(rates.motorcycle)}`;
}

function extractDocumentId(restDocName) {
  const parts = restDocName.split('/');
  return parts[parts.length - 1];
}

function buildTargetDocs({ projectId, sourceDoc, sourceData }) {
  const establishmentId = extractDocumentId(sourceDoc.name);
  const slots = normalizeSlotMap(sourceData.slotCounts || sourceData.slots);
  const rates = normalizeRates(sourceData.ratesByType || sourceData.rates);

  const latitude = ensureNumber(
    sourceData.latitude ?? sourceData.location?.latitude,
    0,
  );
  const longitude = ensureNumber(
    sourceData.longitude ?? sourceData.location?.longitude,
    0,
  );
  const availability = Math.max(
    0,
    Math.trunc(
      ensureNumber(
        sourceData.availability,
        slots.car + slots.motorcycle,
      ),
    ),
  );

  const baseCreatedAt =
    sourceData.createdAt ||
    sourceDoc.createTime ||
    new Date().toISOString();
  const detailsUpdatedAt =
    sourceData.updatedAt ||
    sourceDoc.updateTime ||
    new Date().toISOString();

  const photoUrls = Array.isArray(sourceData.photoUrls) && sourceData.photoUrls.length > 0
    ? sourceData.photoUrls
    : (typeof sourceData.photoUrl === 'string' && sourceData.photoUrl.trim()
        ? [sourceData.photoUrl.trim()]
        : []);

  const establishment = {
    establishmentID: establishmentId,
    ownerId: ensureString(sourceData.ownerId, ''),
    ownerFirstName: ensureString(sourceData.ownerFirstName, ''),
    ownerLastName: ensureString(sourceData.ownerLastName, ''),
    ownerEmail: ensureString(sourceData.ownerEmail, ''),
    name: ensureString(sourceData.name, ''),
    address: ensureString(sourceData.address, ''),
    latitude,
    longitude,
    location: { latitude, longitude },
    operatingHours: ensureString(sourceData.operatingHours, ''),
    availability,
    photoUrls,
    createdAt: baseCreatedAt,
  };

  const activeSlots = {
    car: ensureNumber(sourceData.slots?.car, 0),
    motorcycle: ensureNumber(
      sourceData.slots?.motorcycle,
      0,
    ),
  };

  const details = {
    establishmentID: establishmentId,
    policies: ensureString(sourceData.policies, EXAMPLE_DEFAULTS.policies),
    ratesByType: rates,
    rejectionReason:
      sourceData.rejectionReason === undefined ? null : sourceData.rejectionReason,
    reviewedAt:
      sourceData.reviewedAt === undefined
        ? EXAMPLE_DEFAULTS.reviewedAt
        : sourceData.reviewedAt,
    reviewedBy:
      sourceData.reviewedBy === undefined
        ? EXAMPLE_DEFAULTS.reviewedBy
        : sourceData.reviewedBy,
    slotCounts: slots,
    slots: activeSlots,
    status: ensureString(sourceData.status, EXAMPLE_DEFAULTS.status),
    updatedAt: detailsUpdatedAt,
  };

  return {
    establishmentId,
    establishmentName: documentName(projectId, 'establishments', establishmentId),
    detailsName: documentName(projectId, 'establishment_details', establishmentId),
    establishment,
    details,
  };
}

async function firestoreGet(accessToken, projectId, collection, pageSize, pageToken) {
  const params = new URLSearchParams();
  params.set('pageSize', String(pageSize));
  if (pageToken) {
    params.set('pageToken', pageToken);
  }

  const url = `${FIRESTORE_BASE_URL}/projects/${projectId}/databases/(default)/documents/${collection}?${params.toString()}`;
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Failed to list documents (${response.status}): ${body}`);
  }

  return response.json();
}

async function firestoreCommit(accessToken, projectId, writes) {
  const url = `${FIRESTORE_BASE_URL}/projects/${projectId}/databases/(default)/documents:commit`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ writes }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Commit failed (${response.status}): ${body}`);
  }
}

function toRestFields(doc) {
  const fields = {};
  for (const [k, v] of Object.entries(doc)) {
    fields[k] = toRestValue(v);
  }
  return fields;
}

async function listAllEstablishments(accessToken, projectId, pageSize) {
  const docs = [];
  let pageToken = undefined;

  do {
    const payload = await firestoreGet(
      accessToken,
      projectId,
      'establishments',
      pageSize,
      pageToken,
    );
    const pageDocs = payload.documents || [];
    docs.push(...pageDocs);
    pageToken = payload.nextPageToken;
  } while (pageToken);

  return docs;
}

async function run() {
  const args = parseArgs(process.argv);
  const accessToken = getAccessTokenFromFirebaseTools();

  console.log('Migration target project:', args.project);
  console.log('Mode:', args.apply ? 'APPLY' : 'DRY-RUN');

  if (args.resetLiveSlots) {
    const sourceDocs = await listAllEstablishments(
      accessToken,
      args.project,
      args.pageSize,
    );
    const liveSlots = {
      car: 0,
      motorcycle: 0,
      motor: 0,
    };

    console.log('Resetting live slots for:', sourceDocs.length);
    if (!args.apply) {
      console.log(JSON.stringify(liveSlots, null, 2));
      console.log('Dry-run complete. Re-run with --apply to commit.');
      return;
    }

    for (const sourceDoc of sourceDocs) {
      const establishmentId = extractDocumentId(sourceDoc.name);
      await firestoreCommit(accessToken, args.project, [
        {
          update: {
            name: documentName(
              args.project,
              'establishment_details',
              establishmentId,
            ),
            fields: toRestFields({ slots: liveSlots }),
          },
          updateMask: { fieldPaths: ['slots'] },
        },
      ]);
    }

    console.log(`Live slots reset for ${sourceDocs.length} establishment(s).`);
    return;
  }

  const sourceDocs = await listAllEstablishments(
    accessToken,
    args.project,
    args.pageSize,
  );
  console.log('Found establishments:', sourceDocs.length);

  const transformed = sourceDocs.map((restDoc) => {
    const sourceData = docFromRest(restDoc);
    return buildTargetDocs({
      projectId: args.project,
      sourceDoc: restDoc,
      sourceData,
    });
  });

  const preview = transformed.slice(0, 3).map((item) => ({
    establishmentID: item.establishmentId,
    establishment: item.establishment,
    establishment_details: item.details,
  }));
  console.log('Preview (first up to 3 transformed docs):');
  console.log(JSON.stringify(preview, null, 2));

  if (!args.apply) {
    console.log('Dry-run complete. Re-run with --apply to commit.');
    return;
  }

  let migrated = 0;
  for (const item of transformed) {
    const writes = [
      {
        update: {
          name: item.establishmentName,
          fields: toRestFields(item.establishment),
        },
      },
      {
        update: {
          name: item.detailsName,
          fields: toRestFields(item.details),
        },
      },
    ];

    await firestoreCommit(accessToken, args.project, writes);
    migrated += 1;
    if (migrated % 10 === 0 || migrated === transformed.length) {
      console.log(`Migrated ${migrated}/${transformed.length}`);
    }
  }

  console.log('Migration complete. Total migrated:', migrated);
}

run().catch((error) => {
  console.error('Migration failed:', error.message);
  process.exitCode = 1;
});
