package com.riffhouse.mobile_music_player

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

class PublicFileProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? = null

    override fun getType(uri: Uri): String? = "image/jpeg"

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        android.util.Log.d("PublicFileProvider", "openFile called for URI: $uri")
        val path = uri.path ?: run {
            android.util.Log.e("PublicFileProvider", "URI path is null")
            throw FileNotFoundException("URI path is null")
        }
        val context = context ?: run {
            android.util.Log.e("PublicFileProvider", "Context is null")
            throw FileNotFoundException("Context is null")
        }

        val file: File = if (path.startsWith("/cache/")) {
            val relativePath = path.substring("/cache/".length)
            File(context.cacheDir, relativePath)
        } else if (path.startsWith("/files/")) {
            val relativePath = path.substring("/files/".length)
            File(context.filesDir, relativePath)
        } else {
            android.util.Log.e("PublicFileProvider", "Unsupported path: $path")
            throw FileNotFoundException("Unsupported path: $path")
        }

        // Prevent path traversal attacks
        val canonicalPath = file.canonicalFile.absolutePath
        val cacheCanonical = context.cacheDir.canonicalFile.absolutePath
        val filesCanonical = context.filesDir.canonicalFile.absolutePath
        
        val isUnderCache = canonicalPath.startsWith(cacheCanonical + File.separator) || canonicalPath == cacheCanonical
        val isUnderFiles = canonicalPath.startsWith(filesCanonical + File.separator) || canonicalPath == filesCanonical
        
        if (!isUnderCache && !isUnderFiles) {
            android.util.Log.e("PublicFileProvider", "Access denied (path traversal): canonicalPath=$canonicalPath, cache=$cacheCanonical, files=$filesCanonical")
            throw SecurityException("Access denied: path traversal attempt")
        }

        if (!file.exists()) {
            android.util.Log.e("PublicFileProvider", "File not found: ${file.absolutePath}")
            throw FileNotFoundException("File not found: ${file.absolutePath}")
        }

        android.util.Log.d("PublicFileProvider", "Successfully opened file descriptor for: ${file.absolutePath}")
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }
}
