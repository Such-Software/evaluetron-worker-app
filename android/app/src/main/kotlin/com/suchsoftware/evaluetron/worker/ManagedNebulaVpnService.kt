package com.suchsoftware.evaluetron.worker

import android.content.Intent
import android.net.VpnService
import android.os.IBinder

/**
 * Android VPN privilege boundary for the future embedded Nebula engine.
 *
 * This service intentionally does not establish a TUN interface. Establishing
 * one without a packet engine would black-hole routed traffic. A future engine
 * integration must validate the profile, add only the policy-approved routes,
 * establish the interface, and set [running] only after packet processing is
 * healthy.
 */
class ManagedNebulaVpnService : VpnService() {
    companion object {
        const val ACTION_STOP = "com.suchsoftware.evaluetron.worker.NETWORK_STOP"

        @Volatile
        var running: Boolean = false
            private set
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        running = false
        stopSelf(startId)
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        running = false
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)
}
