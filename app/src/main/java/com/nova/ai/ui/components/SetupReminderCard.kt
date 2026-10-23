package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.setup.SetupChecker

/** A short reminder on the Home screen while some permissions are still missing. */
@Composable
fun SetupReminderCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val checker: SetupChecker = remember { SetupChecker(context) }
    var refreshTick: Int by remember { mutableStateOf(0) }

    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refreshTick += 1
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose { lifecycleOwner?.lifecycle?.removeObserver(observer) }
    }

    val missing: Int = remember(refreshTick) { checker.missingCount() }
    if (missing == 0) return

    NovaInfoCard(
        title = stringResource(R.string.setup_reminder_title),
        body = stringResource(R.string.setup_reminder_body, missing),
        modifier = modifier
    )
}
