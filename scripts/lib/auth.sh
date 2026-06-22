#!/usr/bin/env bash
# ZAP Authentication helper library
# Sources config.sh before using

# Container name for docker exec mode (set by caller)
ZAP_CONTAINER_EXEC=""

# Wrapper for curl that works with both direct and docker exec modes
# Usage: zap_curl <url_args...>
zap_curl() {
  if [[ -n "$ZAP_CONTAINER_EXEC" ]]; then
    docker exec "${ZAP_CONTAINER_EXEC}" curl -s "$@" 2>/dev/null
  else
    curl -s "$@"
  fi
}

# Set up ZAP authentication via API
# Usage: setup_zap_auth <api_url>
# Requires ZAP_AUTH_* variables from config.sh
setup_zap_auth() {
  local api_url="$1"

  if [[ "$ZAP_AUTH_TYPE" == "none" ]] || [[ -z "$ZAP_AUTH_TYPE" ]]; then
    log_info "Authentication: disabled"
    return 0
  fi

  log_info "Setting up authentication (type: ${ZAP_AUTH_TYPE})..."

  case "$ZAP_AUTH_TYPE" in
    form)
      setup_form_auth "$api_url"
      ;;
    form-csrf)
      setup_form_csrf_auth "$api_url"
      ;;
    api)
      setup_api_auth "$api_url"
      ;;
    http-basic)
      setup_basic_auth "$api_url"
      ;;
    *)
      log_error "Unknown auth type: ${ZAP_AUTH_TYPE} (use: form, form-csrf, api, http-basic, none)"
      exit 1
      ;;
  esac
}

# Form-based authentication
setup_form_auth() {
  local api_url="$1"
  local encoded_login_url
  encoded_login_url=$(urlencode "${ZAP_AUTH_LOGIN_URL}")

  if [[ -z "$ZAP_AUTH_LOGIN_URL" ]] || [[ -z "$ZAP_AUTH_USERNAME" ]] || [[ -z "$ZAP_AUTH_PASSWORD" ]]; then
    log_error "Form auth requires: ZAP_AUTH_LOGIN_URL, ZAP_AUTH_USERNAME, ZAP_AUTH_PASSWORD"
    exit 1
  fi

  # Create context
  zap_curl "${api_url}/JSON/context/action/newContext/?contextName=dast" >/dev/null

  # Include target URL in context
  local encoded_target
  encoded_target=$(urlencode "${TARGET_URL}")
  zap_curl "${api_url}/JSON/context/action/includeInContext/?contextName=dast&regex=${encoded_target}.*" >/dev/null

  # Set authentication method
  local login_req_data
  login_req_data=$(urlencode "${ZAP_AUTH_LOGIN_URL}")
  local post_data="${ZAP_AUTH_USERNAME_FIELD}={%25username%25}&${ZAP_AUTH_PASSWORD_FIELD}={%25password%25}"
  zap_curl "${api_url}/JSON/authentication/action/setAuthenticationMethod/?contextId=1&authMethodName=formBasedAuthentication&authMethodConfigParams=loginUrl=${login_req_data}&loginRequestData=${post_data}" >/dev/null

  # Set logged in/out indicators
  if [[ -n "$ZAP_AUTH_LOGGED_IN_INDICATOR" ]]; then
    local encoded_indicator
    encoded_indicator=$(urlencode "${ZAP_AUTH_LOGGED_IN_INDICATOR}")
    zap_curl "${api_url}/JSON/authentication/action/setLoggedInIndicator/?contextId=1&loggedInIndicatorRegex=${encoded_indicator}" >/dev/null
  fi
  if [[ -n "$ZAP_AUTH_LOGGED_OUT_INDICATOR" ]]; then
    local encoded_indicator
    encoded_indicator=$(urlencode "${ZAP_AUTH_LOGGED_OUT_INDICATOR}")
    zap_curl "${api_url}/JSON/authentication/action/setLoggedOutIndicator/?contextId=1&loggedOutIndicatorRegex=${encoded_indicator}" >/dev/null
  fi

  # Create user
  zap_curl "${api_url}/JSON/users/action/newUser/?contextId=1&name=scanner" >/dev/null

  # Set credentials
  local encoded_user
  encoded_user=$(urlencode "${ZAP_AUTH_USERNAME}")
  local encoded_pass
  encoded_pass=$(urlencode "${ZAP_AUTH_PASSWORD}")
  zap_curl "${api_url}/JSON/users/action/setAuthenticationCredentials/?contextId=1&userId=0&authCredentialsConfigParams=username=${encoded_user}&password=${encoded_pass}" >/dev/null

  # Enable user
  zap_curl "${api_url}/JSON/users/action/setUserEnabled/?contextId=1&userId=0&enabled=true" >/dev/null

  # Force initial login
  zap_curl "${api_url}/JSON/authentication/action/login/?contextId=1&pollUrl=&pollData=" >/dev/null

  log_success "Form authentication configured"
}

# Form-based authentication with CSRF token support
# Uses scriptBasedAuthentication to GET the login page, extract a CSRF token,
# and POST credentials along with the token.
setup_form_csrf_auth() {
  local api_url="$1"
  local encoded_login_url
  encoded_login_url=$(urlencode "${ZAP_AUTH_LOGIN_URL}")

  if [[ -z "$ZAP_AUTH_LOGIN_URL" ]] || [[ -z "$ZAP_AUTH_USERNAME" ]] || [[ -z "$ZAP_AUTH_PASSWORD" ]]; then
    log_error "CSRF form auth requires: ZAP_AUTH_LOGIN_URL, ZAP_AUTH_USERNAME, ZAP_AUTH_PASSWORD"
    exit 1
  fi

  local csrf_field="${ZAP_AUTH_CSRF_FIELD:-user_token}"

  # Resolve script path relative to this file
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local script_file="${script_dir}/../zap/auth-csrf.js"

  if [[ ! -f "${script_file}" ]]; then
    log_error "CSRF auth script not found: ${script_file}"
    exit 1
  fi

  # Create context
  zap_curl "${api_url}/JSON/context/action/newContext/?contextName=dast" >/dev/null

  # Include target URL in context
  local encoded_target
  encoded_target=$(urlencode "${TARGET_URL}")
  zap_curl "${api_url}/JSON/context/action/includeInContext/?contextName=dast&regex=${encoded_target}.*" >/dev/null

  # Build POST data template — placeholders ({%username%} etc.) survive URL encoding:
  # urlencode encodes { } % → %7B %7D %25, ZAP decodes once → original literals,
  # which match the .replace() calls in auth-csrf.js exactly.
  local post_data="${ZAP_AUTH_USERNAME_FIELD}={%username%}&${ZAP_AUTH_PASSWORD_FIELD}={%password%}&${csrf_field}={%csrf_token%}"

  # Load the script via ZAP API
  local encoded_script
  encoded_script=$(urlencode "$(cat "${script_file}")")
  zap_curl "${api_url}/JSON/script/action/load/?scriptName=csrfAuth&scriptType=authentication&scriptEngine=Oracle%20Nashorn&scriptDescription=CSRF%20form%20auth&string=${encoded_script}" >/dev/null

  # Set authentication method with parameters
  local encoded_post_data
  encoded_post_data=$(urlencode "${post_data}")
  zap_curl "${api_url}/JSON/authentication/action/setAuthenticationMethod/?contextId=1&authMethodName=scriptBasedAuthentication&authMethodConfigParams=scriptName%3DcsrfAuth%26Login_URL%3D${encoded_login_url}%26CSRF_Field%3D${csrf_field}%26POST_Data%3D${encoded_post_data}" >/dev/null

  # Set logged in/out indicators
  if [[ -n "$ZAP_AUTH_LOGGED_IN_INDICATOR" ]]; then
    local encoded_indicator
    encoded_indicator=$(urlencode "${ZAP_AUTH_LOGGED_IN_INDICATOR}")
    zap_curl "${api_url}/JSON/authentication/action/setLoggedInIndicator/?contextId=1&loggedInIndicatorRegex=${encoded_indicator}" >/dev/null
  fi
  if [[ -n "$ZAP_AUTH_LOGGED_OUT_INDICATOR" ]]; then
    local encoded_indicator
    encoded_indicator=$(urlencode "${ZAP_AUTH_LOGGED_OUT_INDICATOR}")
    zap_curl "${api_url}/JSON/authentication/action/setLoggedOutIndicator/?contextId=1&loggedOutIndicatorRegex=${encoded_indicator}" >/dev/null
  fi

  # Create user
  zap_curl "${api_url}/JSON/users/action/newUser/?contextId=1&name=scanner" >/dev/null

  # Set credentials
  local encoded_user
  encoded_user=$(urlencode "${ZAP_AUTH_USERNAME}")
  local encoded_pass
  encoded_pass=$(urlencode "${ZAP_AUTH_PASSWORD}")
  zap_curl "${api_url}/JSON/users/action/setAuthenticationCredentials/?contextId=1&userId=0&authCredentialsConfigParams=username=${encoded_user}&password=${encoded_pass}" >/dev/null

  # Enable user
  zap_curl "${api_url}/JSON/users/action/setUserEnabled/?contextId=1&userId=0&enabled=true" >/dev/null

  # Force initial login
  zap_curl "${api_url}/JSON/authentication/action/login/?contextId=1&pollUrl=&pollData=" >/dev/null

  log_success "CSRF form authentication configured (field: ${csrf_field})"
}

# API token authentication
setup_api_auth() {
  local api_url="$1"

  if [[ -z "$ZAP_AUTH_API_URL" ]] || [[ -z "$ZAP_AUTH_USERNAME" ]] || [[ -z "$ZAP_AUTH_PASSWORD" ]]; then
    log_error "API auth requires: ZAP_AUTH_API_URL, ZAP_AUTH_USERNAME, ZAP_AUTH_PASSWORD"
    exit 1
  fi

  # First, get the token by calling the login API
  local body="${ZAP_AUTH_API_BODY//__USERNAME__/${ZAP_AUTH_USERNAME}}"
  body="${body//__PASSWORD__/${ZAP_AUTH_PASSWORD}}"

  log_info "Obtaining token from ${ZAP_AUTH_API_URL}..."
  local response
  response=$(zap_curl -X POST "${ZAP_AUTH_API_URL}" \
    -H "Content-Type: application/json" \
    -d "${body}")

  # Extract token
  local token=""
  if [[ -n "$ZAP_AUTH_API_TOKEN_PATH" ]]; then
    token=$(echo "$response" | jq -r ".${ZAP_AUTH_API_TOKEN_PATH} // empty" 2>/dev/null)
  fi

  if [[ -z "$token" ]]; then
    log_error "Failed to extract token from API response (first 100 chars: ${response:0:100})"
    exit 1
  fi

  log_success "Token obtained"

  # Create context
  zap_curl "${api_url}/JSON/context/action/newContext/?contextName=dast" >/dev/null

  # Include target URL in context
  local encoded_target
  encoded_target=$(urlencode "${TARGET_URL}")
  zap_curl "${api_url}/JSON/context/action/includeInContext/?contextName=dast&regex=${encoded_target}.*" >/dev/null

  # Set as HTTP Header or Cookie based auth
  if [[ "$ZAP_AUTH_API_TOKEN_LOCATION" == "header" ]]; then
    local header_name="${ZAP_AUTH_API_TOKEN_HEADER}"
    local header_value="${ZAP_AUTH_API_TOKEN_PREFIX}${token}"

    # Use scripted auth that injects the header
    local script_content
    script_content="function authenticate(helper, paramsValues, credentials) { var request = helper.prepareMessage(); request.getRequestHeader().setHeader('${header_name}', '${header_value}'); return request; }"

    zap_curl "${api_url}/JSON/script/action/load/?scriptName=tokenAuth&scriptType=authentication&scriptEngine=Mozilla%20Rhino&scriptDescription=Token%20auth&string=$(urlencode "${script_content}")" >/dev/null
    zap_curl "${api_url}/JSON/authentication/action/setAuthenticationMethod/?contextId=1&authMethodName=scriptBasedAuthentication&authMethodConfigParams=Script=tokenAuth" >/dev/null
  elif [[ "$ZAP_AUTH_API_TOKEN_LOCATION" == "cookie" ]]; then
    # Set cookie via forced user
    zap_curl "${api_url}/JSON/users/action/newUser/?contextId=1&name=scanner" >/dev/null

    local auth_params="Cookie: ${ZAP_AUTH_API_TOKEN_HEADER}=${token}"
    local encoded_params
    encoded_params=$(urlencode "${auth_params}")
    zap_curl "${api_url}/JSON/users/action/setAuthenticationCredentials/?contextId=1&userId=0&authCredentialsConfigParams=${encoded_params}" >/dev/null
    zap_curl "${api_url}/JSON/users/action/setUserEnabled/?contextId=1&userId=0&enabled=true" >/dev/null
  fi

  log_success "API token authentication configured"
}

# HTTP Basic authentication
setup_basic_auth() {
  local api_url="$1"

  if [[ -z "$ZAP_AUTH_BASIC_USERNAME" ]] || [[ -z "$ZAP_AUTH_BASIC_PASSWORD" ]]; then
    log_error "HTTP Basic auth requires: ZAP_AUTH_BASIC_USERNAME, ZAP_AUTH_BASIC_PASSWORD"
    exit 1
  fi

  # Create context
  zap_curl "${api_url}/JSON/context/action/newContext/?contextName=dast" >/dev/null

  # Include target URL in context
  local encoded_target
  encoded_target=$(urlencode "${TARGET_URL}")
  zap_curl "${api_url}/JSON/context/action/includeInContext/?contextName=dast&regex=${encoded_target}.*" >/dev/null

  # Set authentication method
  zap_curl "${api_url}/JSON/authentication/action/setAuthenticationMethod/?contextId=1&authMethodName=httpAuthentication&authMethodConfigParams=hostname=&port=&realm=" >/dev/null

  # Create user with credentials
  zap_curl "${api_url}/JSON/users/action/newUser/?contextId=1&name=scanner" >/dev/null

  local encoded_user
  encoded_user=$(urlencode "${ZAP_AUTH_BASIC_USERNAME}")
  local encoded_pass
  encoded_pass=$(urlencode "${ZAP_AUTH_BASIC_PASSWORD}")
  zap_curl "${api_url}/JSON/users/action/setAuthenticationCredentials/?contextId=1&userId=0&authCredentialsConfigParams=username=${encoded_user}&password=${encoded_pass}" >/dev/null
  zap_curl "${api_url}/JSON/users/action/setUserEnabled/?contextId=1&userId=0&enabled=true" >/dev/null

  # Force initial login
  zap_curl "${api_url}/JSON/authentication/action/login/?contextId=1&pollUrl=&pollData=" >/dev/null

  log_success "HTTP Basic authentication configured"
}

# URL encode helper (safe for inputs containing single quotes and multiline)
urlencode() {
  printf '%s' "$1" | python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))'
}
