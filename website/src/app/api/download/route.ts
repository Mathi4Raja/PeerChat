import { NextResponse } from "next/server";

/**
 * PeerChat Proxy Download API
 * 
 * This route fetches the latest release from GitHub and redirects the user
 * to the actual APK file. This provides a "straight download" experience
 * and ensures the download link always points to the newest version.
 */

const GITHUB_REPO = "Mathi4Raja/P2P-app";
const GITHUB_LATEST_RELEASE_API = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;

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

        if (!response.ok) {
            console.error("GitHub API error:", response.statusText);
            // Fallback to a hardcoded version if the API is down
            return NextResponse.redirect("https://github.com/Mathi4Raja/P2P-app/releases/download/v1.0.0/PeerChat.apk");
        }

        const release = await response.json();
        
        // 2. Find the APK asset
        // We look for any asset that ends with .apk
        const apkAsset = release.assets?.find((asset: any) => 
            asset.name.toLowerCase().endsWith(".apk")
        );

        if (!apkAsset) {
            return new NextResponse("APK asset not found in the latest release", { status: 404 });
        }

        // 3. Redirect to the download URL
        // We use browser_download_url for a direct browser-initiated download
        return NextResponse.redirect(apkAsset.browser_download_url);

    } catch (error) {
        console.error("Download redirect error:", error);
        return new NextResponse("Internal Server Error", { status: 500 });
    }
}
