'use strict';

// Server-side HTTP for the Lua runtime (see server/core/http.lua). Requests use
// Node's fetch instead of PerformHttpRequest; status 0 means no response.
const REQUEST_TIMEOUT_MS = 30000;

async function performRequest(url, method, body, headers, timeoutMs = REQUEST_TIMEOUT_MS) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: method || 'GET',
      headers: headers || {},
      body: body === undefined || body === null || body === '' ? undefined : String(body),
      signal: controller.signal,
    });
    const text = await response.text();
    const responseHeaders = {};
    response.headers.forEach((value, name) => { responseHeaders[name] = value; });
    return { status: response.status, body: text, headers: responseHeaders, error: null };
  } catch (error) {
    const message = controller.signal.aborted
      ? 'request timed out'
      : String((error && error.cause && error.cause.code) || (error && error.message) || error);
    return { status: 0, body: null, headers: {}, error: message };
  } finally {
    clearTimeout(timer);
  }
}

function handleRequest(id, url, method, body, headers, callback) {
  if (typeof callback !== 'function') return;
  const deliver = (result) => {
    try {
      callback(result.status, result.body, result.headers, result.error);
    } catch (error) {
      console.error(`[humalike] node_http_callback_failed id=${id} error=${error}`);
    }
  };
  if (typeof url !== 'string' || !/^https?:\/\//.test(url)) {
    deliver({ status: 0, body: null, headers: {}, error: 'invalid url' });
    return;
  }
  performRequest(url, method, body, headers).then(deliver);
}

if (typeof exports === 'function' && typeof fetch === 'function'
    && typeof GetCurrentResourceName === 'function') {
  const resourceName = GetCurrentResourceName();
  exports('humalikeNodeHttpRequest', (id, url, method, body, headers, callback) => {
    // Only this resource may send requests carrying its runtime credentials.
    const invoker = typeof GetInvokingResource === 'function' ? GetInvokingResource() : null;
    if (invoker && invoker !== resourceName) {
      throw new Error('humalikeNodeHttpRequest is private to this resource');
    }
    handleRequest(id, url, method, body, headers, callback);
  });
}

if (typeof module === 'object' && module && module.exports) {
  module.exports = { performRequest, handleRequest };
}
