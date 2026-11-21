package dev.hilva.hilva

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingText: String? = null
    private var pendingImages = arrayListOf<String>()
    private var ready = false
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.hilva/native")
        capture(intent)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialText" -> { ready = true; result.success(pendingText); pendingText = null }
                "initialImages" -> { result.success(pendingImages); pendingImages = arrayListOf() }
                "installApk" -> try {
                    val file = File(call.arguments as String).canonicalFile
                    require(file.isFile && file.extension == "apk")
                    val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                    startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                    result.success(null)
                } catch (e: Exception) { result.error("INSTALL", e.message, null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        capture(intent)
    }
    @Suppress("DEPRECATION")
    private fun capture(intent: Intent?) {
        if (intent == null) return
        if (intent.action == "dev.hilva.CAPTURE") {
            if (ready) channel?.invokeMethod("capture", "") else pendingText = ""
        }
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return
        intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.let {
            if (ready) channel?.invokeMethod("capture", it) else pendingText = it
        }
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE)
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: arrayListOf()
        else arrayListOf<Uri>().apply { intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { add(it) } }
        val paths = uris.take(12).mapNotNull { uri ->
            var file: File? = null
            try {
                val mime = contentResolver.getType(uri) ?: return@mapNotNull null
                if (!mime.startsWith("image/")) return@mapNotNull null
                val suffix = when (mime) { "image/png" -> "png"; "image/webp" -> "webp"; "image/gif" -> "gif"; else -> "jpg" }
                val dir = File(filesDir, "shared").apply { mkdirs() }
                val target = File(dir, "${UUID.randomUUID()}.$suffix")
                file = target
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output ->
                        val buffer = ByteArray(8192); var total = 0
                        while (true) { val size = input.read(buffer); if (size < 0) break
                            total += size; require(total <= 25 * 1024 * 1024); output.write(buffer, 0, size) }
                    }
                } ?: return@mapNotNull null
                target.absolutePath
            } catch (_: Exception) { file?.delete(); null }
        }
        if (paths.isNotEmpty()) {
            if (ready) channel?.invokeMethod("images", paths) else pendingImages.addAll(paths)
        }
    }
}
