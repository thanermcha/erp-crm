# How to Clear Browser Cache and Service Worker

Use this after the local machine already resolves `*.growerp.local` and trusts
`docker/certs/growerp.local.crt`. Cache cleanup helps with stale Flutter
assets, but it does not fix missing DNS/hosts entries or TLS trust failures.

## Quick Method (Recommended)

### Chrome/Edge/Brave
1. Open the affected client, for example: `https://admin.growerp.local:8443`
2. Press **Ctrl+Shift+Delete** (or **Cmd+Shift+Delete** on Mac)
3. Select "Cached images and files"
4. Click "Clear data"
5. **Hard refresh**: Press **Ctrl+Shift+R** (or **Cmd+Shift+R** on Mac)

### Firefox
1. Open the affected client, for example: `https://admin.growerp.local:8443`
2. Press **Ctrl+Shift+Delete** (or **Cmd+Shift+Delete** on Mac)
3. Select "Cache"
4. Click "Clear Now"
5. **Hard refresh**: Press **Ctrl+Shift+R** (or **Cmd+Shift+R** on Mac)

## Thorough Method (If Quick Method Doesn't Work)

### Chrome/Edge/Brave
1. Open DevTools: Press **F12**
2. Go to **Application** tab
3. In the left sidebar, find **Service Workers**
4. Click **Unregister** next to the service worker
5. In the left sidebar, find **Cache Storage**
6. Right-click each cache and select **Delete**
7. Close DevTools
8. **Hard refresh**: Press **Ctrl+Shift+R**

### Firefox
1. Open DevTools: Press **F12**
2. Go to **Storage** tab
3. Find **Service Workers** in the left sidebar
4. Click **Unregister** next to the service worker
5. Find **Cache Storage** in the left sidebar
6. Right-click each cache and select **Delete All**
7. Close DevTools
8. **Hard refresh**: Press **Ctrl+Shift+R**

## Verify the Fix

After clearing cache, you can verify the backend URL is correct:

1. Open DevTools (F12)
2. Go to **Console** tab
3. Type: `fetch('/assets/assets/cfg/app_settings.json').then(r => r.json()).then(console.log)`
4. Press Enter
5. Check the output - `databaseUrl` should be `https://backend.growerp.local:8443`

Or check the Network tab:
1. Open DevTools (F12)
2. Go to **Network** tab
3. Filter by "Fetch/XHR"
4. Look for requests - they should go to `https://backend.growerp.local:8443/rest/...`

If the browser console shows `TypeError: Failed to fetch` before any request
appears in the network tab, check `docker/README.md` first for the local hosts
and certificate steps.

## Alternative: Incognito/Private Mode

The easiest way to test without clearing cache:
1. Open a new **Incognito/Private window**
2. Navigate to `https://admin.growerp.local:8443`
3. The app will load fresh without any cached data

## Why This Is Needed

The Flutter service worker aggressively caches assets including
`app_settings.json`. If the browser still serves an older file, the client can
keep calling the wrong backend URL even after the stack has been corrected.
After clearing the cache, the latest client assets and configuration are loaded
again.

## Future Deployments

After this initial cache clear, future deployments should update automatically because:
1. The service worker checks for updates on page load
2. The version.json file changes with each build
3. The service worker will detect the change and update itself

However, if you ever see stale data, just do a hard refresh (Ctrl+Shift+R).
