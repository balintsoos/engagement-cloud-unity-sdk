package com.sap.ec.core.watchdog.connection

internal enum class NetworkConnection {
    None, Wifi, Cellular, Wired, Loopback, Other
}

internal interface Reachability {
    fun subscribeToNetworkChanges(lambda: (Boolean) -> Unit)
    fun isConnected(): Boolean
    fun getNetworkConnection(): NetworkConnection
}
