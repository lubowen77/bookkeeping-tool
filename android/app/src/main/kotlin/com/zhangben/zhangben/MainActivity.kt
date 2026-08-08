package com.zhangben.zhangben

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "zhangben/platform"
        private const val STORAGE_PERMISSION_REQUEST = 6001
        private const val PICK_BACKUP_REQUEST = 6002
        private const val NOTIFICATION_PERMISSION_REQUEST = 6003
        private const val BACKUP_FOLDER = "记账备份"
    }

    private var methodChannel: MethodChannel? = null
    private var pendingBackupUri: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingBackupUri = backupUriFrom(intent) ?: pendingBackupUri
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialBackupUri" -> {
                        result.success(pendingBackupUri)
                        pendingBackupUri = null
                    }
                    "readUri" -> {
                        val uriText = call.argument<String>("uri")
                        if (uriText == null) {
                            result.error("missing_uri", "没有收到备份文件地址", null)
                        } else {
                            readUri(uriText, result)
                        }
                    }
                    "pickBackupFile" -> pickBackupFile(result)
                    "shareBackup" -> {
                        val uri = call.argument<String>("uri")
                        val summary = call.argument<String>("summary")
                        if (uri == null) {
                            result.error("missing_backup", "没有可分享的备份文件", null)
                        } else {
                            shareBackup(uri, summary, result)
                        }
                    }
                    "shareFile" -> {
                        val uri = call.argument<String>("uri")
                        val path = call.argument<String>("path")
                        val mimeType = call.argument<String>("mimeType")
                        val title = call.argument<String>("title")
                        val text = call.argument<String>("text")
                        shareFile(uri ?: path, mimeType, title, text, result)
                    }
                    "scheduleWeeklyBackupReminder" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        if (!enabled) {
                            BackupReminderScheduler.cancel(this)
                            result.success(true)
                        } else {
                            val dayOfWeek = call.argument<Int>("dayOfWeek")
                                ?: BackupReminderScheduler.DEFAULT_DAY_OF_WEEK
                            val hour = call.argument<Int>("hour")
                                ?: BackupReminderScheduler.DEFAULT_HOUR
                            val minute = call.argument<Int>("minute")
                                ?: BackupReminderScheduler.DEFAULT_MINUTE
                            scheduleWeeklyBackupReminder(dayOfWeek, hour, minute, result)
                        }
                    }
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "ensurePublicBackupPermission" -> ensurePublicBackupPermission(result)
                    "writePublicBackup" -> {
                        val fileName = call.argument<String>("fileName")
                        val contents = call.argument<String>("contents")
                        if (fileName == null || contents == null) {
                            result.error("missing_backup", "备份文件名或内容为空", null)
                        } else {
                            writePublicBackup(fileName, contents, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = backupUriFrom(intent) ?: return
        val channel = methodChannel
        if (channel == null) {
            pendingBackupUri = uri
        } else {
            channel.invokeMethod("backupUri", uri)
        }
    }

    private fun backupUriFrom(source: Intent?): String? {
        if (source == null) return null
        return when (source.action) {
            Intent.ACTION_VIEW -> source.data?.toString()
            Intent.ACTION_SEND -> {
                val stream = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    source.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    source.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
                stream?.toString()
            }
            else -> null
        }
    }

    private fun readUri(uriText: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse(uriText)
            result.success(readUriBytes(uri))
        } catch (error: Exception) {
            result.error("read_failed", error.message ?: "读取备份失败", null)
        }
    }

    private fun readUriBytes(uri: Uri): ByteArray {
        return if (uri.scheme == "file") {
            File(requireNotNull(uri.path)).readBytes()
        } else {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("无法打开这个备份文件")
        }
    }

    private fun pickBackupFile(result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("picker_busy", "正在选择备份文件", null)
            return
        }
        pendingPickerResult = result
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/json", "application/octet-stream"),
            )
        }
        try {
            startActivityForResult(picker, PICK_BACKUP_REQUEST)
        } catch (error: Exception) {
            pendingPickerResult = null
            result.error("picker_failed", error.message ?: "无法打开文件选择器", null)
        }
    }

    private fun shareBackup(
        uriText: String,
        summary: String?,
        result: MethodChannel.Result,
    ) {
        try {
            val original = Uri.parse(uriText)
            val uri = if (original.scheme == "file") {
                FileProvider.getUriForFile(
                    this,
                    "$packageName.files",
                    File(requireNotNull(original.path)),
                )
            } else {
                original
            }
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_STREAM, uri)
                if (!summary.isNullOrBlank()) putExtra(Intent.EXTRA_TEXT, summary)
                clipData = ClipData.newUri(contentResolver, "记账本备份", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(share, "分享记账本备份"))
            result.success(null)
        } catch (error: Exception) {
            result.error("share_failed", error.message ?: "分享备份失败", null)
        }
    }

    private fun shareFile(
        uriOrPath: String?,
        mimeType: String?,
        title: String?,
        text: String?,
        result: MethodChannel.Result,
    ) {
        if (uriOrPath.isNullOrBlank()) {
            result.error("missing_file", "没有收到要分享的文件地址", null)
            return
        }
        try {
            val original = Uri.parse(uriOrPath)
            val uri = when {
                original.scheme == null || original.scheme.isNullOrBlank() -> {
                    contentUriForShare(File(uriOrPath))
                }
                original.scheme == "file" -> {
                    contentUriForShare(File(requireNotNull(original.path)))
                }
                original.scheme == "content" -> original
                else -> throw IllegalArgumentException("不支持分享 ${original.scheme} 地址")
            }
            val chooserTitle = title?.takeIf { it.isNotBlank() } ?: "分享文件"
            val share = Intent(Intent.ACTION_SEND).apply {
                type = mimeType?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TITLE, chooserTitle)
                if (!text.isNullOrBlank()) putExtra(Intent.EXTRA_TEXT, text)
                clipData = ClipData.newUri(contentResolver, chooserTitle, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(share, chooserTitle))
            result.success(null)
        } catch (error: Exception) {
            result.error("share_failed", error.message ?: "分享文件失败", null)
        }
    }

    private fun contentUriForShare(file: File): Uri {
        val canonicalFile = file.canonicalFile
        if (!canonicalFile.isFile) {
            throw IllegalArgumentException("要分享的文件不存在")
        }
        val providerRoots = listOf(
            File(filesDir, "exports").canonicalFile,
            File(filesDir, "backups").canonicalFile,
            File(cacheDir, "exports").canonicalFile,
            @Suppress("DEPRECATION")
            File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                BACKUP_FOLDER,
            ).canonicalFile,
        )
        val providerFile = when {
            providerRoots.any { canonicalFile.isInside(it) } -> canonicalFile
            canonicalFile.isInside(File(applicationInfo.dataDir).canonicalFile) -> {
                stagePrivateFileForShare(canonicalFile)
            }
            else -> {
                throw SecurityException("只能分享记账本生成的导出文件")
            }
        }
        return FileProvider.getUriForFile(this, "$packageName.files", providerFile)
    }

    private fun stagePrivateFileForShare(source: File): File {
        val exportDirectory = File(cacheDir, "exports").apply { mkdirs() }
        if (!exportDirectory.isDirectory) {
            throw IllegalStateException("无法创建临时分享目录")
        }
        val safeName = source.name.replace(Regex("[^\\p{L}\\p{N}._-]"), "_")
        val target = File(exportDirectory, "${System.currentTimeMillis()}-$safeName")
        source.inputStream().use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        val now = System.currentTimeMillis()
        exportDirectory.listFiles()
            ?.filter { it.isFile && it != target && now - it.lastModified() > 86_400_000L }
            ?.forEach { it.delete() }
        return target
    }

    private fun File.isInside(root: File): Boolean {
        return path == root.path || path.startsWith(root.path + File.separator)
    }

    private fun scheduleWeeklyBackupReminder(
        dayOfWeek: Int,
        hour: Int,
        minute: Int,
        result: MethodChannel.Result,
    ) {
        try {
            BackupReminderScheduler.schedule(this, dayOfWeek, hour, minute)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            ) {
                result.success(true)
                return
            }
            requestNotificationPermission(result)
        } catch (error: Exception) {
            result.error("reminder_failed", error.message ?: "设置每周备份提醒失败", null)
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error("permission_busy", "正在等待通知权限", null)
            return
        }
        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    @Deprecated("Deprecated in Android; required for FlutterActivity result delivery")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_BACKUP_REQUEST) return
        val callback = pendingPickerResult ?: return
        pendingPickerResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }
        try {
            val uri = requireNotNull(data.data)
            val name = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "选中的备份.jzb"
            callback.success(mapOf("name" to name, "contents" to readUriBytes(uri)))
        } catch (error: Exception) {
            callback.error("read_failed", error.message ?: "读取备份失败", null)
        }
    }

    private fun ensurePublicBackupPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_busy", "正在等待存储权限", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            STORAGE_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        } else if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
        }
    }

    private fun writePublicBackup(
        fileName: String,
        contents: String,
        result: MethodChannel.Result,
    ) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                    put(
                        MediaStore.Downloads.RELATIVE_PATH,
                        "${Environment.DIRECTORY_DOWNLOADS}/$BACKUP_FOLDER/",
                    )
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val uri = contentResolver.insert(collection, values)
                    ?: throw IllegalStateException("无法在 Download 中创建备份")
                try {
                    contentResolver.openOutputStream(uri, "w")?.use {
                        it.write(contents.toByteArray(Charsets.UTF_8))
                    } ?: throw IllegalStateException("无法写入公共备份")
                    values.clear()
                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                } catch (error: Exception) {
                    contentResolver.delete(uri, null, null)
                    throw error
                }
                cleanupMediaStoreBackups(collection)
                result.success(uri.toString())
            } else {
                if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    result.error("permission_denied", "没有公共 Download 写入权限", null)
                    return
                }
                @Suppress("DEPRECATION")
                val download = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val folder = File(download, BACKUP_FOLDER).apply { mkdirs() }
                val file = File(folder, fileName)
                file.writeText(contents, Charsets.UTF_8)
                cleanupLegacyBackups(folder)
                result.success(Uri.fromFile(file).toString())
            }
        } catch (error: Exception) {
            result.error("public_backup_failed", error.message ?: "公共备份写入失败", null)
        }
    }

    private fun cleanupMediaStoreBackups(collection: Uri) {
        val projection = arrayOf(MediaStore.Downloads._ID)
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$BACKUP_FOLDER/"
        contentResolver.query(
            collection,
            projection,
            "${MediaStore.Downloads.RELATIVE_PATH}=?",
            arrayOf(relativePath),
            "${MediaStore.Downloads.DATE_ADDED} DESC, ${MediaStore.Downloads._ID} DESC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID)
            var index = 0
            while (cursor.moveToNext()) {
                if (index >= 60) {
                    val item = Uri.withAppendedPath(collection, cursor.getLong(idColumn).toString())
                    contentResolver.delete(item, null, null)
                }
                index += 1
            }
        }
    }

    private fun cleanupLegacyBackups(folder: File) {
        folder.listFiles { file -> file.isFile && file.extension.equals("jzb", ignoreCase = true) }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(60)
            ?.forEach { it.delete() }
    }
}
