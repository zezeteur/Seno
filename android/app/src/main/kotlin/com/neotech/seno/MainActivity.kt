package com.neotech.seno

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity : requis par local_auth (empreinte / visage)
class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LiveUpdates(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}

