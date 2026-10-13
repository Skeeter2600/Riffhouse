package com.riffhouse.mobile_music_player

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves cached artwork to Android Auto and the system media controls, which
 * run in other processes and cannot send the Jellyfin auth header themselves.
 *
 * The provider is exported, so any app on the device can call it. It therefore
 * only ever hands out artwork: files in the image cache folder, or the
 * `art_*.jpg` files the audio handler downloads into the cache root. Nothing
 * else in the cache (such as a downloaded update) is reachable.
 */
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
        val context = context ?: throw FileNotFoundException("No context")
        val path = uri.path ?: throw FileNotFoundException("URI has no path")
        if (!path.startsWith(CACHE_PREFIX)) {
            throw FileNotFoundException("Unsupported path")
        }

        // Resolve symlinks and ".." before checking where the file really is.
        val cacheDir = context.cacheDir.canonicalFile
        val file = File(cacheDir, path.substring(CACHE_PREFIX.length)).canonicalFile
        if (!isArtwork(file, cacheDir)) {
            throw SecurityException("Access denied")
        }
        if (!file.isFile) {
            throw FileNotFoundException("File not found")
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun isArtwork(file: File, cacheDir: File): Boolean {
        val parent = file.parentFile ?: return false
        val imageCache = File(cacheDir, IMAGE_CACHE_DIR)
        if (parent == imageCache) return true
        return parent == cacheDir &&
            file.name.startsWith("art_") && file.name.endsWith(".jpg")
    }

    private companion object {
        const val CACHE_PREFIX = "/cache/"

        // Folder used by flutter_cache_manager's default cache.
        const val IMAGE_CACHE_DIR = "libCachedImageData"
    }
}
