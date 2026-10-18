package com.unicornsonlsd.finamp

import androidx.core.content.FileProvider

/** Shares downloaded updates with Android's installer. Its own class, so it can't clash with other file providers. */
class UpdateFileProvider : FileProvider()
