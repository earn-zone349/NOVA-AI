package com.nova.ai.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.nova.ai.ui.screens.AiBrainScreen
import com.nova.ai.ui.screens.AutomationScreen
import com.nova.ai.ui.screens.HomeScreen
import com.nova.ai.ui.screens.MemoryScreen
import com.nova.ai.ui.screens.PermissionsScreen
import com.nova.ai.ui.screens.PrivacySecurityScreen

/** Main app frame: bottom navigation bar plus the screen host. */
@Composable
fun NovaMainScaffold() {
    val navController: NavHostController = rememberNavController()

    Scaffold(
        bottomBar = { NovaBottomBar(navController) }
    ) { innerPadding ->
        NovaNavGraph(
            navController = navController,
            modifier = Modifier.padding(innerPadding)
        )
    }
}

/** Maps every [NovaDestination] route to its screen. */
@Composable
fun NovaNavGraph(
    navController: NavHostController,
    modifier: Modifier = Modifier
) {
    NavHost(
        navController = navController,
        startDestination = NovaDestination.HOME.route,
        modifier = modifier
    ) {
        composable(NovaDestination.HOME.route) { HomeScreen() }
        composable(NovaDestination.BRAIN.route) { AiBrainScreen() }
        composable(NovaDestination.AUTOMATION.route) { AutomationScreen() }
        composable(NovaDestination.PERMISSIONS.route) { PermissionsScreen() }
        composable(NovaDestination.MEMORY.route) { MemoryScreen() }
        composable(NovaDestination.PRIVACY.route) { PrivacySecurityScreen() }
    }
}

@Composable
private fun NovaBottomBar(navController: NavHostController) {
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute: String? = backStackEntry?.destination?.route

    NavigationBar {
        NovaDestination.values().forEach { destination ->
            NavigationBarItem(
                selected = currentRoute == destination.route,
                onClick = {
                    navController.navigate(destination.route) {
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                },
                icon = { Text(text = destination.iconEmoji) },
                label = {
                    Text(
                        text = stringResource(destination.labelRes),
                        style = MaterialTheme.typography.labelSmall,
                        maxLines = 1,
                        softWrap = false
                    )
                }
            )
        }
    }
}
