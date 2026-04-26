import { NextResponse } from "next/server";

/**
 * PeerChat Proxy Download API
 * 
 * This route fetches the latest release from GitHub and redirects the user
 * to the actual APK file. This provides a "straight download" experience
 * and ensures the download link always points to the newest version.
 */

const GITHUB_REPO = "Mathi4Raja/PeerChat";
const GITHUB_LATEST_RELEASE_API = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;

export const dynamic = 'force-dynamic';

export async function GET() {
    try {
        const headers: Record<string, string> = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        };

        // Use GITHUB_TOKEN if available to avoid rate limits
        if (process.env.GITHUB_TOKEN) {
            headers["Authorization"] = `Bearer ${process.env.GITHUB_TOKEN}`;
        }

        // 1. Get the latest release information
        const response = await fetch(GITHUB_LATEST_RELEASE_API, { 
            headers,
            next: { revalidate: 3600 } // Cache the response for 1 hour
        });

        // --- FALLBACK CONFIG ---
        // If the GitHub API fails, these values will be used as a safety net.
        // Update these occasionally to the latest stable version.
        let downloadUrl = "https://github.com/Mathi4Raja/PeerChat/releases/download/v1.0.1/PeerChat-v1.0.1.apk";
        let filename = "PeerChat-v1.0.1.apk";

        if (response.ok) {
            const release = await response.json();
            
            // 2. Find the APK asset
            const apkAsset = release.assets?.find((asset: any) => 
                asset.name.toLowerCase().endsWith(".apk")
            );

            if (apkAsset) {
                downloadUrl = apkAsset.browser_download_url;
                filename = apkAsset.name;
            }
        }

        // 3. Redirect to the download URL with optimization headers
        // We use a 302 redirect and manually add headers to hint the download
        const redirectResponse = NextResponse.redirect(downloadUrl, 302);
        
        // Add headers to the redirect response to help mobile browsers
        redirectResponse.headers.set('Content-Disposition', `attachment; filename="${filename}"`);
        redirectResponse.headers.set('Content-Type', 'application/vnd.android.package-archive');
        redirectResponse.headers.set('Cache-Control', 'no-store, max-age=0');

        return redirectResponse;

    } catch (error) {
        console.error("Download redirect error:", error);
        return new NextResponse("Internal Server Error", { status: 500 });
    }
}
