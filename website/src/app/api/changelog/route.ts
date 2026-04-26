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
            next: { revalidate: 120 } // Refresh every 2 minutes
        });

        if (!response.ok) {
            return new NextResponse("Failed to fetch releases", { status: 502 });
        }

        const releases = await response.json();
        
        interface GitHubRelease {
            body: string;
            tag_name: string;
            published_at: string;
            name: string;
        }

        // Map GitHub release data to our website's expected format
        const formattedReleases = (releases as GitHubRelease[]).map((rel) => {
            let changes: string[] = rel.body 
                ? rel.body.split('\n')
                    .map((l: string) => l.trim())
                    .filter((l: string) => l.length > 0 && !l.startsWith('**Full Changelog**'))
                : ["Initial production release."];

            // If we have bullet points, prioritize them
            const bullets = changes.filter((l: string) => l.startsWith('-') || l.startsWith('*') || l.startsWith('•'));
            if (bullets.length > 0) {
                changes = bullets.map((b: string) => b.replace(/^[-*•]\s*/, ''));
            }

            return {
                version: rel.tag_name,
                date: new Date(rel.published_at).toLocaleDateString('en-US', {
                    year: 'numeric',
                    month: 'long',
                    day: 'numeric'
                }),
                tag: rel.name || "Release",
                changes: changes.length > 0 ? changes : ["General improvements and bug fixes."]
            };
        });

        return NextResponse.json(formattedReleases);

    } catch (error) {
        console.error("Changelog fetch error:", error);
        return new NextResponse("Internal Server Error", { status: 500 });
    }
}
