// ZAP scriptBasedAuthentication script for CSRF-protected form login
// Loaded by setup_form_csrf_auth in auth.sh
//
// Expected paramsValues:
//   Login_URL  - URL of the login page (GET to extract token, POST to login)
//   CSRF_Field - name attribute of the hidden CSRF token input
//   POST_Data  - URL-encoded POST body template with placeholders:
//                {%username%}, {%password%}, {%csrf_token%}

function authenticate(helper, paramsValues, credentials) {
  var HttpMessage = Java.type('org.parosproxy.paros.network.HttpMessage');
  var URI = Java.type('org.apache.commons.httpclient.URI');
  var sender = helper.getHttpSender();

  // GET login page to extract CSRF token
  var msg = new HttpMessage(new URI(paramsValues['Login_URL'], true));
  sender.sendAndReceive(msg, true);
  var body = msg.getResponseBody().toString();

  // Extract CSRF token from hidden input field (supports name/value in any order,
  // with optional extra attributes between them)
  var fieldName = paramsValues['CSRF_Field'];
  var re1 = new RegExp('name=["\x27]' + fieldName + '["\x27][^>]*value=["\x27]([^"\x27]+)', 'i');
  var re2 = new RegExp('value=["\x27]([^"\x27]+)["\x27][^>]*name=["\x27]' + fieldName + '["\x27]', 'i');
  var match = re1.exec(body) || re2.exec(body);
  var token = match ? match[1] : '';

  // Build POST body with credentials and CSRF token
  var postData = paramsValues['POST_Data'];
  postData = postData.replace('{%username%}', credentials.getUsername());
  postData = postData.replace('{%password%}', credentials.getPassword());
  postData = postData.replace('{%csrf_token%}', encodeURIComponent(token));

  // POST login request
  var loginMsg = new HttpMessage(new URI(paramsValues['Login_URL'], true));
  loginMsg.getRequestHeader().setMethod('POST');
  loginMsg.getRequestHeader().setHeader('Content-Type', 'application/x-www-form-urlencoded');
  loginMsg.setRequestBody(postData);
  loginMsg.getRequestHeader().setContentLength(loginMsg.getRequestBody().length());
  sender.sendAndReceive(loginMsg, true);
  return loginMsg;
}
