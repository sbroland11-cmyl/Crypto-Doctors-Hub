/**
 * CDH Spark-compatible backend
 *
 * Deploy this Google Apps Script as a Web App owned/executed by the CDH
 * Google account. It uses Google Drive for media and Firestore for secure
 * metadata/payment state. Firebase ID tokens are validated through Firebase
 * Authentication before user-scoped actions are accepted.
 *
 * IMPORTANT:
 * - Never put a Drive refresh token/service-account private key in Flutter.
 * - Set Script Properties listed in README before deployment.
 * - Automatic blockchain verification requires the corresponding network API
 *   keys. No entitlement is granted by the Flutter client.
 */

const CONFIG = {
  PROJECT_ID: 'crypto-doctors-hub',
  FIREBASE_API_KEY_PROPERTY: 'CDH_FIREBASE_WEB_API_KEY',
  DRIVE_ROOT_PROPERTY: 'CDH_DRIVE_ROOT_FOLDER_ID',
  PROXY_SECRET_PROPERTY: 'CDH_PROXY_SECRET',
  TRON_API_KEY_PROPERTY: 'CDH_TRONGRID_API_KEY',
  ETHERSCAN_API_KEY_PROPERTY: 'CDH_ETHERSCAN_API_KEY',
};

function doPost(e) {
  try {
    const body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    const action = String(body.action || '').trim();
    switch (action) {
      case 'upload': return json_(upload_(body));
      case 'download': return json_(download_(body));
      case 'createOrder': return json_(createOrder_(body));
      case 'submitTxHash': return json_(submitTxHash_(body));
      case 'getOrder': return json_(getOrder_(body));
      case 'scanPendingOrders': return json_(scanPendingOrders_(body));
      default: return json_({ ok: false, error: 'Unsupported backend action.' });
    }
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  }
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}

function props_() { return PropertiesService.getScriptProperties(); }

function firebaseApiKey_() {
  const key = props_().getProperty(CONFIG.FIREBASE_API_KEY_PROPERTY);
  if (!key) throw new Error('Missing CDH_FIREBASE_WEB_API_KEY Script Property.');
  return key;
}

function validateFirebaseToken_(idToken) {
  if (!idToken) throw new Error('Firebase authentication token is required.');
  const url = 'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=' + encodeURIComponent(firebaseApiKey_());
  const response = UrlFetchApp.fetch(url, {
    method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    payload: JSON.stringify({ idToken: idToken }),
  });
  const code = response.getResponseCode();
  const data = JSON.parse(response.getContentText() || '{}');
  if (code < 200 || code >= 300 || !data.users || !data.users.length) throw new Error('Firebase authentication failed.');
  return data.users[0];
}

function firestoreUrl_(path) {
  return 'https://firestore.googleapis.com/v1/projects/' + CONFIG.PROJECT_ID + '/databases/(default)/documents/' + path;
}

function firestoreRequest_(method, path, payload) {
  const options = {
    method: method,
    muteHttpExceptions: true,
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
    contentType: 'application/json',
  };
  if (payload !== undefined) options.payload = JSON.stringify(payload);
  const response = UrlFetchApp.fetch(firestoreUrl_(path), options);
  const code = response.getResponseCode();
  const text = response.getContentText() || '{}';
  if (code < 200 || code >= 300) throw new Error('Firestore request failed: ' + code + ' ' + text.slice(0, 500));
  return JSON.parse(text);
}

function encodeFields_(data) {
  const fields = {};
  Object.keys(data || {}).forEach(function(k) { fields[k] = encodeValue_(data[k]); });
  return fields;
}

function encodeValue_(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue_) } };
  if (typeof v === 'object') return { mapValue: { fields: encodeFields_(v) } };
  return { stringValue: String(v) };
}

function decodeFields_(fields) {
  const out = {};
  Object.keys(fields || {}).forEach(function(k) { out[k] = decodeValue_(fields[k]); });
  return out;
}

function decodeValue_(v) {
  if (!v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('booleanValue' in v) return !!v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if (v.arrayValue) return (v.arrayValue.values || []).map(decodeValue_);
  if (v.mapValue) return decodeFields_(v.mapValue.fields || {});
  return null;
}

function firestoreGet_(path) {
  try { return decodeFields_(firestoreRequest_('get', path).fields || {}); }
  catch (err) {
    if (String(err).indexOf('404') >= 0) return null;
    throw err;
  }
}

function firestoreSet_(path, data) {
  const fields = encodeFields_(data);
  const masks = Object.keys(fields).map(function(k) { return 'updateMask.fieldPaths=' + encodeURIComponent(k); }).join('&');
  const url = firestoreUrl_(path) + (masks ? '?' + masks : '');
  const response = UrlFetchApp.fetch(url, {
    method: 'patch', muteHttpExceptions: true,
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
    contentType: 'application/json',
    payload: JSON.stringify({ fields: fields }),
  });
  const code = response.getResponseCode();
  if (code < 200 || code >= 300) throw new Error('Firestore write failed: ' + code + ' ' + response.getContentText().slice(0, 500));
  return true;
}

function upload_(body) {
  const auth = validateFirebaseToken_(body.idToken);
  const uid = String(body.ownerUid || auth.localId || '').trim();
  if (uid !== String(auth.localId)) throw new Error('User identity mismatch.');
  const bytes = Utilities.base64Decode(String(body.dataBase64 || ''));
  if (!bytes.length) throw new Error('Empty upload.');
  if (bytes.length > 45 * 1024 * 1024) throw new Error('File is too large for the Drive bridge. Maximum is 45 MB per bridge upload.');

  const rootId = props_().getProperty(CONFIG.DRIVE_ROOT_PROPERTY);
  if (!rootId) throw new Error('Missing CDH_DRIVE_ROOT_FOLDER_ID Script Property.');
  const root = DriveApp.getFolderById(rootId);
  const scope = String(body.scope || 'general').replace(/[^A-Za-z0-9_:-]/g, '_');
  const folder = ensureFolderPath_(root, [scope, uid]);
  const fileName = String(body.fileName || ('upload_' + Date.now())).replace(/[^A-Za-z0-9._-]/g, '_');
  const blob = Utilities.newBlob(bytes, String(body.contentType || 'application/octet-stream'), fileName);
  const file = folder.createFile(blob);

  firestoreSet_('driveFiles/' + file.getId(), {
    fileId: file.getId(), ownerUid: uid, scope: scope, name: fileName,
    contentType: String(body.contentType || 'application/octet-stream'),
    sizeBytes: bytes.length, createdAt: new Date().toISOString(),
  });
  return { ok: true, fileRef: file.getId() };
}

function ensureFolderPath_(root, parts) {
  let current = root;
  parts.forEach(function(part) {
    const existing = current.getFoldersByName(part);
    current = existing.hasNext() ? existing.next() : current.createFolder(part);
  });
  return current;
}

function canReadDriveFile_(auth, meta) {
  if (!meta) return false;
  const uid = String(auth.localId || '');
  if (meta.ownerUid === uid) return true;
  if (meta.scope === 'payment_proof') return isBackendAdmin_(uid);
  if (String(meta.scope || '').indexOf('mentorship') === 0) {
    if (isBackendAdmin_(uid)) return true;
    const user = firestoreGet_('users/' + uid) || {};
    return user.mentorshipApproved === true || user.studentApproved === true || user.isStudent === true;
  }
  return isBackendAdmin_(uid);
}

function isBackendAdmin_(uid) {
  const user = firestoreGet_('users/' + uid) || {};
  return user.role === 'admin' || user.admin === true;
}

function download_(body) {
  const auth = validateFirebaseToken_(body.idToken);
  const fileId = String(body.fileId || '').trim();
  if (!fileId) throw new Error('Drive file ID is required.');
  const meta = firestoreGet_('driveFiles/' + fileId);
  if (!canReadDriveFile_(auth, meta)) throw new Error('You are not allowed to read this file.');
  const file = DriveApp.getFileById(fileId);
  const bytes = file.getBlob().getBytes();
  if (bytes.length > 45 * 1024 * 1024) throw new Error('File is too large for the Drive bridge download.');
  return { ok: true, dataBase64: Utilities.base64Encode(bytes), contentType: file.getMimeType(), name: file.getName() };
}

function createOrder_(body) {
  const auth = validateFirebaseToken_(body.idToken);
  const uid = auth.localId;
  const product = String(body.product || '').trim();
  const planId = String(body.planId || '').trim();
  const network = normalizeNetwork_(body.network);
  if (!['premium', 'mentorship', 'verified_creator'].includes(product)) throw new Error('Unsupported automatic payment product.');
  if (!['trc20', 'bep20', 'erc20'].includes(network)) throw new Error('Select a supported USDT network.');

  const config = firestoreGet_('paymentSettings/config') || {};
  const plans = config.plans || {};
  const plan = plans[planId] || null;
  if (!plan || plan.enabled === false) throw new Error('This payment plan is not available.');
  let baseAmount = Number(plan.amount || 0);
  if (planId === 'mentorship_installment') baseAmount = 20;
  if (!(baseAmount > 0)) throw new Error('Payment plan amount is not configured.');

  const methods = Array.isArray(config.paymentMethods) ? config.paymentMethods : [];
  const method = methods.find(function(m) { return String(m.id || '').toLowerCase() === network; });
  if (!method || method.enabled === false || !String(method.details || '').trim()) throw new Error('The selected network receiving address is not configured by Admin.');

  const uniqueAmount = Number((baseAmount + (Math.floor(Math.random() * 89) + 11) / 100).toFixed(2));
  const orderId = Utilities.getUuid();
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString();
  const username = String((firestoreGet_('users/' + uid) || {}).username || auth.email || 'User');
  firestoreSet_('paymentOrders/' + orderId, {
    orderId: orderId, userId: uid, username: username, email: auth.email || '',
    product: product, planId: planId, planName: String(plan.name || planId),
    baseAmount: baseAmount, amount: uniqueAmount, currency: 'USDT', network: network,
    destination: String(method.details || '').trim(), status: 'awaiting_payment',
    createdAt: new Date().toISOString(), expiresAt: expiresAt,
  });
  return { ok: true, orderId: orderId, order: firestoreGet_('paymentOrders/' + orderId) };
}

function submitTxHash_(body) {
  const auth = validateFirebaseToken_(body.idToken);
  const orderId = String(body.orderId || '').trim();
  const hash = String(body.transactionHash || '').trim();
  if (!orderId || !hash) throw new Error('Order ID and transaction hash are required.');
  const order = firestoreGet_('paymentOrders/' + orderId);
  if (!order) throw new Error('Payment order not found.');
  if (order.userId !== auth.localId) throw new Error('Order ownership mismatch.');
  if (order.status === 'paid') return { ok: true, status: 'paid', order: order };
  if (new Date(order.expiresAt).getTime() < Date.now()) throw new Error('This payment order has expired. Create a new order.');
  firestoreSet_('paymentOrders/' + orderId, { ...order, transactionHash: hash, status: 'submitted', submittedAt: new Date().toISOString() });
  const verification = verifyTransaction_(order, hash);
  if (verification.ok) {
    finalizePayment_(orderId, verification);
    const updated = firestoreGet_('paymentOrders/' + orderId);
    return { ok: true, status: 'paid', order: updated };
  }
  return { ok: true, status: 'pending_verification', message: verification.message || 'Transaction has not been confirmed yet.' };
}

function getOrder_(body) {
  const auth = validateFirebaseToken_(body.idToken);
  const order = firestoreGet_('paymentOrders/' + String(body.orderId || '').trim());
  if (!order || order.userId !== auth.localId) throw new Error('Payment order not found.');
  return { ok: true, order: order };
}

function normalizeNetwork_(network) {
  const value = String(network || '').toLowerCase();
  if (value.indexOf('trc') >= 0) return 'trc20';
  if (value.indexOf('bep') >= 0) return 'bep20';
  if (value.indexOf('erc') >= 0 || value.indexOf('eth') >= 0) return 'erc20';
  return value;
}

function verifyTransaction_(order, hash) {
  if (order.network === 'trc20') return verifyTron_(order, hash);
  if (order.network === 'bep20') return verifyEvm_(order, hash, 56, 18);
  if (order.network === 'erc20') return verifyEvm_(order, hash, 1, 6);
  return { ok: false, message: 'Unsupported network.' };
}

function verifyEvm_(order, hash, chainId, decimals) {
  const key = props_().getProperty(CONFIG.ETHERSCAN_API_KEY_PROPERTY);
  if (!key) return { ok: false, message: 'Etherscan API key is not configured in the backend yet.' };
  const contract = chainId === 56 ? '0x55d398326f99059ff775485246999027b3197955' : '0xdAC17F958D2ee523a2206206994597C13D831ec7';
  const url = 'https://api.etherscan.io/v2/api?chainid=' + chainId + '&module=account&action=tokentx&contractaddress=' + contract + '&address=' + encodeURIComponent(order.destination) + '&page=1&offset=100&sort=desc&apikey=' + encodeURIComponent(key);
  const response = UrlFetchApp.fetch(url, { muteHttpExceptions: true });
  const data = JSON.parse(response.getContentText() || '{}');
  const rows = Array.isArray(data.result) ? data.result : [];
  const target = rows.find(function(row) {
    const value = Number(row.value || 0) / Math.pow(10, decimals);
    return String(row.hash || '').toLowerCase() === hash.toLowerCase()
      && String(row.to || '').toLowerCase() === String(order.destination || '').toLowerCase()
      && Math.abs(value - Number(order.amount || 0)) < 0.000001
      && String(row.contractAddress || '').toLowerCase() === contract.toLowerCase();
  });
  if (!target) return { ok: false, message: 'Transaction not yet found with the exact destination and amount.' };
  return { ok: true, network: order.network, hash: hash, from: target.from, amount: Number(target.value) / Math.pow(10, decimals), block: target.blockNumber };
}

function verifyTron_(order, hash) {
  const apiKey = props_().getProperty(CONFIG.TRON_API_KEY_PROPERTY);
  const headers = apiKey ? { 'TRON-PRO-API-KEY': apiKey } : {};
  const url = 'https://api.trongrid.io/v1/accounts/' + encodeURIComponent(order.destination) + '/transactions/trc20?limit=100&only_confirmed=true&order_by=block_timestamp,desc';
  const response = UrlFetchApp.fetch(url, { muteHttpExceptions: true, headers: headers });
  const data = JSON.parse(response.getContentText() || '{}');
  const rows = Array.isArray(data.data) ? data.data : [];
  const target = rows.find(function(row) {
    const decimals = Number(row.token_info && row.token_info.decimals || 6);
    const value = Number(row.value || 0) / Math.pow(10, decimals);
    return String(row.transaction_id || '').toLowerCase() === hash.toLowerCase()
      && String(row.to || '') === String(order.destination || '')
      && Math.abs(value - Number(order.amount || 0)) < 0.000001
      && String(row.token_info && row.token_info.symbol || '').toUpperCase() === 'USDT';
  });
  if (!target) return { ok: false, message: 'Transaction not yet found on TRON with the exact destination and amount.' };
  return { ok: true, network: 'trc20', hash: hash, from: target.from, amount: Number(order.amount), block: target.block_timestamp };
}

function finalizePayment_(orderId, verification) {
  const order = firestoreGet_('paymentOrders/' + orderId);
  if (!order || order.status === 'paid') return;
  const now = new Date().toISOString();
  firestoreSet_('paymentTransactions/' + orderId, {
    transactionId: orderId, orderId: orderId, userId: order.userId,
    product: order.product, planId: order.planId, amount: order.amount, currency: 'USDT',
    network: order.network, destination: order.destination, transactionHash: order.transactionHash || verification.hash,
    status: 'confirmed', confirmedAt: now, verification: verification,
  });
  grantEntitlement_(order, now);
  firestoreSet_('paymentOrders/' + orderId, { ...order, status: 'paid', paidAt: now, verification: verification });
}

function grantEntitlement_(order, now) {
  const uid = order.userId;
  const userPath = 'users/' + uid;
  const user = firestoreGet_(userPath) || {};
  if (order.product === 'premium') {
    const badgeType = order.planId === 'premium_one_time' ? 'premium_lifetime' : 'premium_monthly';
    firestoreSet_(userPath, { ...user, isPremium: true, premiumStatus: 'approved', premiumPlan: order.planId, premiumApprovedAt: now, updatedAt: now });
    firestoreSet_(userPath + '/badgeEntitlements/' + badgeType, { badgeId: badgeType, badgeType: badgeType, eligible: true, status: 'available', source: 'automatic_payment', createdAt: now, updatedAt: now });
    firestoreSet_(userPath + '/mail/payment_' + orderIdSafe_(order.orderId), { type: 'payment', title: 'PREMIUM PAYMENT CONFIRMED', body: 'Your Premium payment was confirmed automatically on the blockchain. Open Mail to collect your Premium badge.', badgeIds: [badgeType], badgeType: badgeType, readAt: null, createdAt: now });
    return;
  }
  if (order.product === 'verified_creator') {
    firestoreSet_(userPath, { verifiedCreatorApproved: true, verifiedCreatorPaymentStatus: 'approved', verifiedCreatorPlan: order.planId, verifiedCreatorApprovedAt: now, updatedAt: now });
    firestoreSet_(userPath + '/mail/payment_' + orderIdSafe_(order.orderId), { type: 'verification', title: 'VERIFIED CREATOR PAYMENT CONFIRMED', body: 'Your Verified Creator payment was confirmed automatically. Your application can continue through the Admin review process.', readAt: null, createdAt: now });
    return;
  }
  if (order.product === 'mentorship') {
    if (order.planId === 'mentorship_one_time') {
      firestoreSet_(userPath, { ...user, mentorshipApproved: true, studentApproved: true, isStudent: true, studentStatus: 'Student', mentorshipPaymentPlan: 'one_time', mentorshipPaymentStatus: 'completed', mentorshipApprovedAt: now, updatedAt: now });
      firestoreSet_(userPath + '/badgeEntitlements/mentorship_one_time', { badgeId: 'mentorship_one_time', badgeType: 'mentorship_one_time', eligible: true, status: 'available', source: 'automatic_payment', createdAt: now, updatedAt: now });
      firestoreSet_(userPath + '/mail/payment_' + orderIdSafe_(order.orderId), { type: 'payment', title: 'MENTORSHIP PAYMENT CONFIRMED', body: 'Your Mentorship payment was confirmed automatically. Open Mail to collect your Student badge.', badgeIds: ['mentorship_one_time'], badgeType: 'mentorship_one_time', readAt: null, createdAt: now });
      return;
    }
    const paymentPath = 'mentorshipPayments/' + uid;
    const payment = firestoreGet_(paymentPath) || {};
    const paidWeeks = Number(payment.paidWeeks || 0) + 1;
    const stage = Math.min(paidWeeks, 4);
    const completed = stage >= 4;
    firestoreSet_(paymentPath, { ...payment, uid: uid, plan: 'installment', totalAmount: 80, weeklyAmount: 20, weeks: 4, paidWeeks: stage, paymentStatus: completed ? 'completed' : 'current', lastInstallmentPaidAt: now, nextInstallmentDueAt: completed ? null : new Date(Date.now() + 7 * 86400000).toISOString(), updatedAt: now });
    firestoreSet_(userPath, { ...user, mentorshipApproved: true, studentApproved: true, isStudent: true, studentStatus: 'Student', mentorshipPaymentPlan: 'installment', mentorshipPaymentStatus: completed ? 'completed' : 'current', installmentPaidWeeks: stage, lastInstallmentPaidAt: now, updatedAt: now });
    const badge = 'mentorship_installment_' + stage;
    firestoreSet_(userPath + '/badgeEntitlements/' + badge, { badgeId: badge, badgeType: badge, eligible: true, status: 'available', studentStage: stage, graduated: false, source: 'automatic_payment', createdAt: now, updatedAt: now });
    firestoreSet_(userPath + '/mail/payment_' + orderIdSafe_(order.orderId), { type: 'payment', title: 'MENTORSHIP INSTALLMENT ' + stage + ' CONFIRMED', body: 'Your Mentorship installment ' + stage + ' was confirmed automatically. Open Mail to collect your Student ' + stage + ' badge. Student 4 remains separate from Graduated.', badgeIds: [badge], badgeType: badge, studentStage: stage, graduated: false, readAt: null, createdAt: now });
  }
}

function orderIdSafe_(id) { return String(id || '').replace(/[^A-Za-z0-9_-]/g, '_'); }

function firestoreQuery_(collectionId, field, value) {
  const url = 'https://firestore.googleapis.com/v1/projects/' + CONFIG.PROJECT_ID + '/databases/(default)/documents:runQuery';
  const query = {
    structuredQuery: {
      from: [{ collectionId: collectionId }],
      where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: encodeValue_(value) } },
      limit: 100,
    },
  };
  const response = UrlFetchApp.fetch(url, {
    method: 'post', muteHttpExceptions: true,
    headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
    contentType: 'application/json', payload: JSON.stringify(query),
  });
  const code = response.getResponseCode();
  if (code < 200 || code >= 300) throw new Error('Firestore query failed: ' + code + ' ' + response.getContentText().slice(0, 500));
  const rows = JSON.parse(response.getContentText() || '[]');
  return rows.filter(function(row) { return row.document; }).map(function(row) {
    const name = String(row.document.name || '');
    const id = name.split('/').pop();
    return { id: id, data: decodeFields_(row.document.fields || {}) };
  });
}

function installScannerTrigger_() {
  ScriptApp.getProjectTriggers().forEach(function(trigger) {
    if (trigger.getHandlerFunction() === 'scheduledPaymentScanner') ScriptApp.deleteTrigger(trigger);
  });
  ScriptApp.newTrigger('scheduledPaymentScanner').timeBased().everyMinutes(5).create();
}

function scheduledPaymentScanner() {
  scanPendingOrdersInternal_();
}

function scanPendingOrdersInternal_() {
  const pending = [];
  ['awaiting_payment', 'submitted'].forEach(function(status) {
    firestoreQuery_('paymentOrders', 'status', status).forEach(function(row) { pending.push(row); });
  });
  const seen = {};
  let confirmed = 0;
  pending.forEach(function(row) {
    if (seen[row.id]) return;
    seen[row.id] = true;
    const order = row.data || {};
    if (!order.expiresAt || new Date(order.expiresAt).getTime() < Date.now()) {
      firestoreSet_('paymentOrders/' + row.id, { ...order, status: 'expired', expiredAt: new Date().toISOString() });
      return;
    }
    const found = findRecentTransfer_(order);
    if (found && found.ok) {
      order.orderId = row.id;
      order.transactionHash = found.hash;
      finalizePayment_(row.id, found);
      confirmed++;
    }
  });
  return { scanned: pending.length, confirmed: confirmed };
}

function findRecentTransfer_(order) {
  if (order.network === 'trc20') return findTronTransfer_(order);
  if (order.network === 'bep20') return findEvmTransfer_(order, 56, 18);
  if (order.network === 'erc20') return findEvmTransfer_(order, 1, 6);
  return null;
}

function findEvmTransfer_(order, chainId, decimals) {
  const key = props_().getProperty(CONFIG.ETHERSCAN_API_KEY_PROPERTY);
  if (!key) return null;
  const contract = chainId === 56 ? '0x55d398326f99059ff775485246999027b3197955' : '0xdAC17F958D2ee523a2206206994597C13D831ec7';
  const url = 'https://api.etherscan.io/v2/api?chainid=' + chainId + '&module=account&action=tokentx&contractaddress=' + contract + '&address=' + encodeURIComponent(order.destination) + '&page=1&offset=100&sort=desc&apikey=' + encodeURIComponent(key);
  const response = UrlFetchApp.fetch(url, { muteHttpExceptions: true });
  const data = JSON.parse(response.getContentText() || '{}');
  const rows = Array.isArray(data.result) ? data.result : [];
  const created = new Date(order.createdAt || 0).getTime();
  const target = rows.find(function(row) {
    const value = Number(row.value || 0) / Math.pow(10, decimals);
    const txTime = Number(row.timeStamp || 0) * 1000;
    return String(row.to || '').toLowerCase() === String(order.destination || '').toLowerCase()
      && String(row.contractAddress || '').toLowerCase() === contract.toLowerCase()
      && Math.abs(value - Number(order.amount || 0)) < 0.000001
      && txTime >= created
      && txTime <= Date.now()
      && String(row.isError || '0') === '0';
  });
  if (!target) return null;
  return { ok: true, network: order.network, hash: String(target.hash || ''), from: target.from, amount: Number(target.value) / Math.pow(10, decimals), block: target.blockNumber };
}

function findTronTransfer_(order) {
  const apiKey = props_().getProperty(CONFIG.TRON_API_KEY_PROPERTY);
  const headers = apiKey ? { 'TRON-PRO-API-KEY': apiKey } : {};
  const url = 'https://api.trongrid.io/v1/accounts/' + encodeURIComponent(order.destination) + '/transactions/trc20?limit=100&only_confirmed=true&order_by=block_timestamp,desc';
  const response = UrlFetchApp.fetch(url, { muteHttpExceptions: true, headers: headers });
  const data = JSON.parse(response.getContentText() || '{}');
  const rows = Array.isArray(data.data) ? data.data : [];
  const created = new Date(order.createdAt || 0).getTime();
  const target = rows.find(function(row) {
    const decimals = Number(row.token_info && row.token_info.decimals || 6);
    const value = Number(row.value || 0) / Math.pow(10, decimals);
    return String(row.to || '') === String(order.destination || '')
      && String(row.token_info && row.token_info.symbol || '').toUpperCase() === 'USDT'
      && Math.abs(value - Number(order.amount || 0)) < 0.000001
      && Number(row.block_timestamp || 0) >= created;
  });
  if (!target) return null;
  return { ok: true, network: 'trc20', hash: String(target.transaction_id || ''), from: target.from, amount: Number(order.amount), block: target.block_timestamp };
}

function scanPendingOrders_(body) {
  const auth = validateFirebaseToken_(body.idToken);
  if (!isBackendAdmin_(auth.localId)) throw new Error('Admin access required.');
  return { ok: true, ...scanPendingOrdersInternal_() };
}
