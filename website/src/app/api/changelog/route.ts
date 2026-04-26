import { NextResponse } from "next/server";

/**
 * PeerChat Changelog API
 * 
 * This route fetches all releases from GitHub to provide a dynamic
 * changelog for the website.
 */

const GITHUB_REPO = "Mathi4Raja/PeerChat";
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
            next: { revalidate: 120 } 
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

        const formattedReleases = (releases as GitHubRelease[]).map((rel) => {
            const rawLines = rel.body ? rel.body.split('\n').map(l => l.trim()) : [];
            const items: { category: string; text: string }[] = [];
            let currentCategory = "App"; // Default

            rawLines.forEach(line => {
                if (line.length === 0 || line.startsWith('**Full Changelog**')) return;

                // Detect category switches from headings
                const lowerLine = line.toLowerCase();
                if (line.startsWith('#')) {
                    if (lowerLine.includes('web')) currentCategory = "Web";
                    else if (lowerLine.includes('app') || lowerLine.includes('mobile')) currentCategory = "App";
                    return;
                }

                // Parse bullet points
                if (line.startsWith('-') || line.startsWith('*') || line.startsWith('•')) {
                    const text = line.replace(/^[-*•]\s*/, '');
                    
                    // Smart category detection
                    let category = currentCategory;
                    const lowerText = text.toLowerCase();
                    
                    // Web Keywords
                    const webKeywords = ['website', 'ui polish', 'css', 'layout', 'responsive', 'seo', 'meta', 'footer', 'header', 'nav', 'hero', 'animation', 'section', 'browser'];
                    // App Keywords
                    const appKeywords = ['apk', 'app', 'mesh', 'ble', 'bluetooth', 'wifi', 'hotspot', 'transfer', 'encryption', 'p2p', 'mobile', 'android', 'notification'];

                    if (webKeywords.some(k => lowerText.includes(k))) category = "Web";
                    else if (appKeywords.some(k => lowerText.includes(k))) category = "App";

                    items.push({ category, text });
                }
            });

            return {
                version: rel.tag_name,
                date: new Date(rel.published_at).toLocaleDateString('en-US', {
                    year: 'numeric',
                    month: 'long',
                    day: 'numeric'
                }),
                tag: rel.name || "Release",
                changes: items.length > 0 ? items : [{ category: "General", text: "General improvements and bug fixes." }]
            };
        });

        return NextResponse.json(formattedReleases);

    } catch (error) {
        console.error("Changelog fetch error:", error);
        return new NextResponse("Internal Server Error", { status: 500 });
    }
}
