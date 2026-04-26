import { NextResponse } from "next/server";

/**
 * PeerChat Changelog API
 * 
 * This route fetches all releases from GitHub to provide a dynamic
 * changelog for the website.
 */

const GITHUB_REPO = "Mathi4Raja/P2P-app";
const GITHUB_RELEASES_API = `https://api.github.com/repos/${GITHUB_REPO}/releases`;

export async function GET() {
    try {
        const headers: Record<string, string> = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        };

        if (process.env.GITHUB_TOKEN) {
            headers["Authorization"] = `Bearer ${process.env.GITHUB_TOKEN}`;
        }

        const response = await fetch(GITHUB_RELEASES_API, { 
            headers,
            next: { revalidate: 3600 } // Cache for 1 hour
        });

        if (!response.ok) {
            return new NextResponse("Failed to fetch releases", { status: 502 });
        }

        const releases = await response.json();
        
        // Map GitHub release data to our website's expected format
        const formattedReleases = releases.map((rel: any) => ({
            version: rel.tag_name,
            date: new Date(rel.published_at).toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            }),
            tag: rel.name || "Release",
            // GitHub release body is markdown, we can pass it directly 
            // or split into lines if needed. 
            changes: rel.body ? rel.body.split('\n').filter((l: string) => l.trim().startsWith('-') || l.trim().startsWith('*')) : []
        }));

        return NextResponse.json(formattedReleases);

    } catch (error) {
        console.error("Changelog fetch error:", error);
        return new NextResponse("Internal Server Error", { status: 500 });
    }
}
