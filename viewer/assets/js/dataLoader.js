/**
 * SimTreeNav Data Loader
 * Handles loading and parsing of data files with basePath support
 */

const DataLoader = (function() {
    'use strict';

    /**
     * Fetch JSON file with error handling
     */
    async function fetchJSON(url) {
        try {
            const response = await fetch(url);
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            return await response.json();
        } catch (error) {
            console.error(`Failed to load ${url}:`, error);
            throw error;
        }
    }

    /**
     * Load manifest and configure basePath
     */
    async function loadManifest() {
        // Try to load manifest from current location first
        const manifestPaths = [
            'manifest.json',
            './manifest.json',
            'data/manifest.json',
            './data/manifest.json'
        ];

        let manifest = null;
        for (const path of manifestPaths) {
            try {
                manifest = await fetchJSON(path);
                break;
            } catch (e) {
                continue;
            }
        }

        if (!manifest) {
            console.warn('No manifest.json found, using defaults');
            manifest = {
                schemaVersion: '0.6.0',
                viewer: { basePath: '' },
                files: {}
            };
        }

        // Configure basePath from manifest
        const basePath = manifest.viewer?.basePath || '';
        AppState.set('config.basePath', basePath);
        AppState.set('manifest', manifest);

        return manifest;
    }

    /**
     * Load all data files based on manifest
     */
    async function loadAllData(manifest) {
        const files = manifest.files || {};
        const loaders = [];

        // Required files
        if (files.nodes || true) {
            loaders.push(
                loadNodes(files.nodes || 'nodes.json')
                    .catch(e => { console.warn('nodes.json not found:', e); return null; })
            );
        }

        // Optional files
        if (files.timeline) {
            loaders.push(
                loadTimeline(files.timeline)
                    .catch(e => { console.warn('timeline.json not found:', e); return null; })
            );
        }

        if (files.diff) {
            loaders.push(
                loadDiff(files.diff)
                    .catch(e => { console.warn('diff.json not found:', e); return null; })
            );
        }

        if (files.actions) {
            loaders.push(
                loadActions(files.actions)
                    .catch(e => { console.warn('actions.json not found:', e); return null; })
            );
        }

        if (files.impact) {
            loaders.push(
                loadImpact(files.impact)
                    .catch(e => { console.warn('impact.json not found:', e); return null; })
            );
        }

        if (files.drift) {
            loaders.push(
                loadDrift(files.drift)
                    .catch(e => { console.warn('drift.json not found:', e); return null; })
            );
        }

        await Promise.all(loaders);
    }

    /**
     * Load nodes data
     */
    async function loadNodes(filename = 'nodes.json') {
        const url = AppState.resolveDataPath(filename);
        const nodes = await fetchJSON(url);
        AppState.set('nodes', nodes);
        AppState.buildIndexes();
        return nodes;
    }

    /**
     * Load timeline data
     */
    async function loadTimeline(filename = 'timeline.json') {
        const url = AppState.resolveDataPath(filename);
        const timeline = await fetchJSON(url);
        AppState.set('timeline', timeline);
        return timeline;
    }

    /**
     * Load diff data
     */
    async function loadDiff(filename = 'diff.json') {
        const url = AppState.resolveDataPath(filename);
        const diff = await fetchJSON(url);
        AppState.set('diff', diff);

        // Mark changed nodes
        if (diff && diff.changes) {
            const changedNodes = AppState.get('derived.changedNodes');
            for (const change of diff.changes) {
                if (change.nodeId) {
                    changedNodes.add(change.nodeId);
                }
            }
        }

        return diff;
    }

    /**
     * Load actions data
     */
    async function loadActions(filename = 'actions.json') {
        const url = AppState.resolveDataPath(filename);
        const actions = await fetchJSON(url);
        AppState.set('actions', actions);
        return actions;
    }

    /**
     * Load impact data
     */
    async function loadImpact(filename = 'impact.json') {
        const url = AppState.resolveDataPath(filename);
        const impact = await fetchJSON(url);
        AppState.set('impact', impact);
        return impact;
    }

    /**
     * Load drift data
     */
    async function loadDrift(filename = 'drift.json') {
        const url = AppState.resolveDataPath(filename);
        const drift = await fetchJSON(url);
        AppState.set('drift', drift);
        return drift;
    }

    /**
     * Load drift trend data
     */
    async function loadDriftTrend(filename = 'drift_trend.json') {
        const url = AppState.resolveDataPath(filename);
        const driftTrend = await fetchJSON(url);
        AppState.set('driftTrend', driftTrend);
        return driftTrend;
    }

    /**
     * Initialize data loading
     */
    async function init() {
        try {
            const manifest = await loadManifest();
            await loadAllData(manifest);
            AppState.emit('dataLoaded');
            return true;
        } catch (error) {
            console.error('Failed to initialize data:', error);
            AppState.emit('dataError', error);
            return false;
        }
    }

    // Public API
    return {
        init,
        loadManifest,
        loadAllData,
        loadNodes,
        loadTimeline,
        loadDiff,
        loadActions,
        loadImpact,
        loadDrift,
        loadDriftTrend,
        fetchJSON
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = DataLoader;
}
