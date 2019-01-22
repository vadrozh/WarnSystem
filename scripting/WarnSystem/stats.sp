/***************************************
 *         Stats module by             *
 *     Kruzya aka CrazyHackGUT         *
 ***************************************
 */

bool g_bSteamWorks;
bool g_bSocket;
bool g_bCURL;

void STATS_OnLibraryAdded(const char[] szLib)
{
    if (StrEqual(szLib, "SteamWorks"))
        g_bSteamWorks = true;
    else if (StrEqual(szLib, "socket"))
        g_bSocket = true;
    else if (StrEqual(szLib, "curl"))
        g_bCURL = true;
}

void STATS_OnLibraryRemoved(const char[] szLib)
{
    if (StrEqual(szLib, "SteamWorks"))
        g_bSteamWorks = false;
    else if (StrEqual(szLib, "socket"))
        g_bSocket = false;
    else if (StrEqual(szLib, "curl"))
        g_bCURL = false;
}

void InitializeStats()
{
    g_bSteamWorks   = LibraryExists("SteamWorks");
    g_bSocket       = LibraryExists("socket");
    g_bCURL         = LibraryExists("curl");
}

void STATS_MarkNativesAsOptional()
{
    // Curl natives do not marks "optional" automatically, lol
    MarkNativeAsOptional("curl_easy_setopt_function");
    MarkNativeAsOptional("curl_easy_perform_thread");
    MarkNativeAsOptional("curl_easy_setopt_string");
    MarkNativeAsOptional("curl_easy_setopt_handle");
    MarkNativeAsOptional("curl_easy_setopt_int");
    MarkNativeAsOptional("curl_easy_strerror");
    MarkNativeAsOptional("curl_slist_append");
    MarkNativeAsOptional("curl_easy_init");
    MarkNativeAsOptional("curl_slist");

    // Socket natives do not marks "optional" automatically, lol
    MarkNativeAsOptional("SocketConnect");
    MarkNativeAsOptional("SocketCreate");
    MarkNativeAsOptional("SocketSetArg");
    MarkNativeAsOptional("SocketSend");
}

void STATS_AddServer(const char[] szKey, const char[] szVersion) {
    if (g_bSteamWorks) {
        STATS_SteamWorks_AddServer(szKey, szVersion);
    } else if (g_bCURL) {
        STATS_CURL_AddServer(szKey, szVersion);
    } else if (g_bSocket) {
        STATS_Socket_AddServer(szKey, szVersion);
    } else {
        LogWarnings("Can't add server to SM plugin statistics. Not found any compatible extension. (SteamWorks, cURL, socket)");
    }
}

void STATS_GetIP(char[] szBuffer, int iMaxLength) {
    if (g_bSteamWorks) {
        STATS_SteamWorks_GetIP(szBuffer, iMaxLength);
    } else {
        STATS_Generic_GetIP(szBuffer, iMaxLength);
    }
}

void STATS_Generic_GetIP(char[] szBuffer, int iMaxLength) {
    int iHostIP = FindConVar("hostip").IntValue;
    FormatEx(szBuffer, iMaxLength, "%d.%d.%d.%d:%d", (iHostIP >> 24) & 0x000000FF, (iHostIP >> 16) & 0x000000FF, (iHostIP >>  8) & 0x000000FF, iHostIP & 0x000000FF, FindConVar("hostport").IntValue);
}

/**
 * SteamWorks
 */
void STATS_SteamWorks_AddServer(const char[] szKey, const char[] szVersion) {
    char szRequest[256];
    char szIP[65];
    STATS_GetIP(szIP, sizeof(szIP));
    FormatEx(szRequest, sizeof(szRequest), "key=%s&ip=%s&version=%s", szKey, szIP, szVersion);

    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, PLUGIN_STATS_REQURL);
    SteamWorks_SetHTTPRequestRawPostBody(hRequest, "application/x-www-form-urlencoded", szRequest, sizeof(szRequest));
    SteamWorks_SetHTTPCallbacks(hRequest, STATS_SteamWorks_OnTransferComplete);
    SteamWorks_SendHTTPRequest(hRequest);
}

void STATS_SteamWorks_GetIP(char[] szBuffer, int iMaxLength) {
    int iIP[4];
    SteamWorks_GetPublicIP(iIP);

    FormatEx(szBuffer, iMaxLength, "%d.%d.%d.%d:%d", iIP[0], iIP[1], iIP[2], iIP[3], FindConVar("hostport").IntValue);
}

public int STATS_SteamWorks_OnTransferComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode) {
    delete hRequest;
    switch(eStatusCode) {
        case k_EHTTPStatusCode200OK:                    LogAction(-1, -1, "[WarnSystem] Server successfully added/refreshed");
        case k_EHTTPStatusCode400BadRequest:            LogWarnings("[WarnSystem] Bad request");
        case k_EHTTPStatusCode403Forbidden:             LogWarnings("[WarnSystem] IP:Port is incorrect");
        case k_EHTTPStatusCode404NotFound:              LogWarnings("[WarnSystem] Server or version doesn't exists");
        case k_EHTTPStatusCode406NotAcceptable:         LogWarnings("[WarnSystem] APIKEY is incorrect");
        case k_EHTTPStatusCode413RequestEntityTooLarge: LogWarnings("[WarnSystem] Request Entity Too Large");
    }
}

/**
 * cURL
 */
void STATS_CURL_AddServer(const char[] szKey, const char[] szVersion) {
    char szRequest[256];
    char szIP[65];
    STATS_GetIP(szIP, sizeof(szIP));
    FormatEx(szRequest, sizeof(szRequest), "key=%s&ip=%s&version=%s", szKey, szIP, szVersion);

    Handle hBuffer = curl_slist();
    curl_slist_append(hBuffer, "User-Agent: Valve/Steam HTTP Client 1.0");

    Handle hCurl = curl_easy_init();
    curl_easy_setopt_function(hCurl,    CURLOPT_WRITEFUNCTION,  STATS_CURL_OnWrite);
    curl_easy_setopt_string(hCurl,      CURLOPT_URL,            PLUGIN_STATS_REQURL);
    curl_easy_setopt_string(hCurl,      CURLOPT_POSTFIELDS,     szRequest);
    curl_easy_setopt_handle(hCurl,      CURLOPT_HTTPHEADER,     hBuffer);
    curl_easy_setopt_int(hCurl,         CURLOPT_POSTFIELDSIZE,  strlen(szRequest));
    curl_easy_setopt_int(hCurl,         CURLOPT_HTTPPOST,       1);
    curl_easy_perform_thread(hCurl,     STATS_CURL_OnComplete,  hBuffer);
}

public int STATS_CURL_OnWrite(Handle hCurl, const char[] szBuffer, const int bytes, const int nmemb) {
    if(!strcmp(szBuffer, "Success!")) {
        LogAction(-1, -1, "[WarnSystem] Server successfully added/refreshed");
    } else {
        LogWarnings("[WarnSystem] Can't add/refresh server (%s)", szBuffer);
    }

    return bytes*nmemb;
}

public int STATS_CURL_OnComplete(Handle hCurl, CURLcode code, any hHeader) {
    CloseHandle(hCurl);
    CloseHandle(hHeader);

    if (code != CURLE_OK) {
        char szError[256];
        curl_easy_strerror(code, szError, sizeof(szError));
        LogWarnings("[WarnSystem] cURL error: [%i] %s", code, szError);
    }
}

/**
 * Socket.
 */
void STATS_Socket_AddServer(const char[] szKey, const char[] szVersion) {
    Handle hPack = CreateDataPack();
    WritePackString(hPack, szKey);
    WritePackString(hPack, szVersion);

    Handle hSocket = SocketCreate(SOCKET_TCP, STATS_Socket_OnError);
    SocketSetArg(hSocket, hPack);
    SocketConnect(hSocket, STATS_Socket_OnConnected, STATS_Socket_OnReceive, STATS_Socket_OnDisconnected, PLUGIN_STATS_DOMAIN, 80);
}

public int STATS_Socket_OnConnected(Handle hSocket, any arg) {
    char szRequest[512];
    char szParams[129];
    char szIP[65];
    STATS_GetIP(szIP, sizeof(szIP));

    char szKey[40];
    char szVersion[10];
    ResetPack(arg);
    ReadPackString(arg, szKey, sizeof(szKey));
    ReadPackString(arg, szVersion, sizeof(szVersion));

    FormatEx(szParams, sizeof(szParams), "key=%s&ip=%s&version=%s", szKey, szIP, szVersion);
    FormatEx(szRequest, sizeof(szRequest), "POST /%s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\nContent-Length: %i\r\nUser-Agent: Valve/Steam HTTP Client 1.0\r\nContent-Type: application/x-www-form-urlencoded\r\n\r\n%s\r\n", PLUGIN_STATS_SCRIPT, PLUGIN_STATS_DOMAIN, strlen(szParams), szParams);

    SocketSend(hSocket, szRequest);
}

public int STATS_Socket_OnReceive(Handle hSocket, const char[] szReceiveData, const int iDataSize, any arg) {
    int iStartIndex = FindCharInString(szReceiveData, ' ');
    if(iStartIndex != -1) {
        char szBuffer[4];
        strcopy(szBuffer, sizeof(szBuffer), szReceiveData[iStartIndex+1]);
        szBuffer[3] = 0;
        switch(StringToInt(szBuffer)) {
            case 200:   LogAction(-1, -1, "[WarnSystem] Server successfully added/refreshed");
            case 400:   LogWarnings("[WarnSystem] Bad request");
            case 403:   LogWarnings("[WarnSystem] IP:Port is incorrect");
            case 404:   LogWarnings("[WarnSystem] Server or version doesn't exists");
            case 406:   LogWarnings("[WarnSystem] APIKEY is incorrect");
            case 413:   LogWarnings("[WarnSystem] Request Entity Too Large");
        }
    }
}

public int STATS_Socket_OnDisconnected(Handle hSocket, any data) {
    CloseHandle(hSocket);
    CloseHandle(data);
}

public int STATS_Socket_OnError(Handle hSocket, const int iErrorType, const int iErrorNum, any data) {
    LogWarnings("[WarnSystem] OnSocketError: Error Type %d, Error Num %d", iErrorType, iErrorNum);
    STATS_Socket_OnDisconnected(hSocket, data);
}