package com.suchsoftware.evaluetron.worker

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val NETWORK_CHANNEL = "com.suchsoftware.evaluetron.worker/network"
        private const val CAMERA_CHANNEL = "com.suchsoftware.evaluetron.worker/camera"
        private const val VPN_CONSENT_REQUEST = 0x4556
    }

    private var pendingVpnConsent: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NETWORK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "inspect" -> {
                    result.success(
                        mapOf(
                            "platformSupported" to true,
                            "engineLinked" to false,
                            "vpnPermissionGranted" to (VpnService.prepare(this) == null),
                            "running" to ManagedNebulaVpnService.running,
                            "detail" to
                                "Android VPN consent is wired; the pinned Nebula engine is not linked.",
                        ),
                    )
                }

                "requestVpnConsent" -> requestVpnConsent(result)
                "start" ->
                    result.error(
                        "engine_unavailable",
                        "The audited Nebula engine is not linked in this build.",
                        null,
                    )

                "stop" -> {
                    stopService(
                        Intent(this, ManagedNebulaVpnService::class.java).apply {
                            action = ManagedNebulaVpnService.ACTION_STOP
                        },
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CAMERA_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "inspect" -> result.success(CameraProbe.inspect(this))

                // Opening cameras blocks while the HAL answers, so it is kept
                // off the platform thread. The measurement is worthless if the
                // wait for it distorts the timings being measured.
                "measureSwitch" -> measureCameraSwitch(call, result)

                else -> result.notImplemented()
            }
        }
    }

    private fun measureCameraSwitch(call: MethodCall, result: MethodChannel.Result) {
        val firstId = call.argument<String>("firstId")
        val secondId = call.argument<String>("secondId")
        if (firstId == null || secondId == null) {
            result.error("bad_arguments", "Two camera ids are required.", null)
            return
        }
        val rounds = call.argument<Int>("rounds") ?: 5
        Thread {
            val outcome = runCatching {
                CameraProbe.measureSwitch(this, firstId, secondId, rounds)
            }
            runOnUiThread {
                outcome.fold(
                    onSuccess = result::success,
                    onFailure = { error ->
                        result.error(
                            "probe_failed",
                            error.message ?: "The camera switch probe failed.",
                            null,
                        )
                    },
                )
            }
        }.start()
    }

    private fun requestVpnConsent(result: MethodChannel.Result) {
        if (pendingVpnConsent != null) {
            result.error("consent_pending", "A VPN consent request is already open.", null)
            return
        }
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success("granted")
            return
        }
        pendingVpnConsent = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, VPN_CONSENT_REQUEST)
    }

    @Deprecated("Required by the FlutterActivity embedding for VPN consent results")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VPN_CONSENT_REQUEST) {
            val result = pendingVpnConsent
            pendingVpnConsent = null
            result?.success(if (resultCode == Activity.RESULT_OK) "granted" else "denied")
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        pendingVpnConsent?.success("cancelled")
        pendingVpnConsent = null
        super.onDestroy()
    }
}
