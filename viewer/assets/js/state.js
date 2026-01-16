/**
 * SimTreeNav State Management
 * Centralized state store for the viewer application
 */

const AppState = (function() {
    'use strict';

    // Private state
    let state = {
        // Configuration
        config: {
            basePath: '',
            schemaVersion: '0.6.0',
            maxNodesInViewer: 10000
        },

        // Data
        manifest: null,
        timeline: null,
        nodes: null,
        diff: null,
        actions: null,
        impact: null,
        drift: null,
        driftTrend: null,

        // UI State
        ui: {
            selectedNodeId: null,
            expandedNodes: new Set(),
            changedOnlyMode: false,
            searchQuery: '',
            filters: {
                nodeType: null,
                severity: null,
                stationPrefix: null
            },
            currentSnapshot: null,
            compareSnapshot: null,
            viewMode: 'timeline' // 'timeline', 'actions', 'diffs'
        },

        // Derived data (computed from nodes)
        derived: {
            nodeIndex: new Map(),
            parentIndex: new Map(),
            changedNodes: new Set(),
            visibleNodes: [],
            flattenedTree: []
        }
    };

    // Event listeners
    const listeners = new Map();

    // Public API
    return {
        /**
         * Get current state value
         */
        get(path) {
            const parts = path.split('.');
            let current = state;
            for (const part of parts) {
                if (current === undefined || current === null) return undefined;
                current = current[part];
            }
            return current;
        },

        /**
         * Set state value and notify listeners
         */
        set(path, value) {
            const parts = path.split('.');
            let current = state;
            for (let i = 0; i < parts.length - 1; i++) {
                if (current[parts[i]] === undefined) {
                    current[parts[i]] = {};
                }
                current = current[parts[i]];
            }
            const lastPart = parts[parts.length - 1];
            const oldValue = current[lastPart];
            current[lastPart] = value;

            // Notify listeners
            this.emit(path, value, oldValue);
            this.emit('stateChange', { path, value, oldValue });
        },

        /**
         * Subscribe to state changes
         */
        on(event, callback) {
            if (!listeners.has(event)) {
                listeners.set(event, new Set());
            }
            listeners.get(event).add(callback);
            return () => this.off(event, callback);
        },

        /**
         * Unsubscribe from state changes
         */
        off(event, callback) {
            if (listeners.has(event)) {
                listeners.get(event).delete(callback);
            }
        },

        /**
         * Emit state change event
         */
        emit(event, ...args) {
            if (listeners.has(event)) {
                listeners.get(event).forEach(cb => {
                    try {
                        cb(...args);
                    } catch (e) {
                        console.error('State listener error:', e);
                    }
                });
            }
        },

        /**
         * Get the base path for loading data files
         */
        getBasePath() {
            return state.config.basePath || '';
        },

        /**
         * Resolve a data file path using basePath
         */
        resolveDataPath(filename) {
            const base = this.getBasePath();
            if (!base) return `data/${filename}`;
            return `${base.replace(/\/$/, '')}/data/${filename}`;
        },

        /**
         * Resolve an asset path using basePath
         */
        resolveAssetPath(filename) {
            const base = this.getBasePath();
            if (!base) return `assets/${filename}`;
            return `${base.replace(/\/$/, '')}/assets/${filename}`;
        },

        /**
         * Check if a node is expanded
         */
        isExpanded(nodeId) {
            return state.ui.expandedNodes.has(nodeId);
        },

        /**
         * Toggle node expansion
         */
        toggleExpand(nodeId) {
            if (state.ui.expandedNodes.has(nodeId)) {
                state.ui.expandedNodes.delete(nodeId);
            } else {
                state.ui.expandedNodes.add(nodeId);
            }
            this.emit('expansionChange', nodeId);
        },

        /**
         * Expand all nodes
         */
        expandAll() {
            if (!state.nodes) return;
            state.nodes.forEach(node => {
                if (node.children && node.children.length > 0) {
                    state.ui.expandedNodes.add(node.id);
                }
            });
            this.emit('expansionChange', 'all');
        },

        /**
         * Collapse all nodes
         */
        collapseAll() {
            state.ui.expandedNodes.clear();
            this.emit('expansionChange', 'all');
        },

        /**
         * Select a node
         */
        selectNode(nodeId) {
            const oldId = state.ui.selectedNodeId;
            state.ui.selectedNodeId = nodeId;
            this.emit('selectionChange', nodeId, oldId);
        },

        /**
         * Get selected node
         */
        getSelectedNode() {
            if (!state.ui.selectedNodeId || !state.derived.nodeIndex) return null;
            return state.derived.nodeIndex.get(state.ui.selectedNodeId);
        },

        /**
         * Set changed-only mode
         */
        setChangedOnlyMode(enabled) {
            state.ui.changedOnlyMode = enabled;
            this.emit('filterChange', 'changedOnly', enabled);
        },

        /**
         * Set search query
         */
        setSearchQuery(query) {
            state.ui.searchQuery = query;
            this.emit('searchChange', query);
        },

        /**
         * Build derived indexes from nodes data
         */
        buildIndexes() {
            if (!state.nodes) return;

            state.derived.nodeIndex.clear();
            state.derived.parentIndex.clear();

            const buildIndex = (nodes, parentId = null) => {
                for (const node of nodes) {
                    state.derived.nodeIndex.set(node.id, node);
                    if (parentId !== null) {
                        state.derived.parentIndex.set(node.id, parentId);
                    }
                    if (node.children) {
                        buildIndex(node.children, node.id);
                    }
                }
            };

            if (Array.isArray(state.nodes)) {
                buildIndex(state.nodes);
            } else if (state.nodes.root) {
                buildIndex([state.nodes.root]);
            }

            this.emit('indexesBuilt');
        },

        /**
         * Get node by ID
         */
        getNode(nodeId) {
            return state.derived.nodeIndex.get(nodeId);
        },

        /**
         * Get parent node ID
         */
        getParentId(nodeId) {
            return state.derived.parentIndex.get(nodeId);
        },

        /**
         * Get ancestors of a node (for expand-to-node)
         */
        getAncestors(nodeId) {
            const ancestors = [];
            let currentId = nodeId;
            while (currentId) {
                const parentId = state.derived.parentIndex.get(currentId);
                if (parentId) {
                    ancestors.unshift(parentId);
                }
                currentId = parentId;
            }
            return ancestors;
        },

        /**
         * Expand ancestors to reveal a node
         */
        expandToNode(nodeId) {
            const ancestors = this.getAncestors(nodeId);
            for (const ancestorId of ancestors) {
                state.ui.expandedNodes.add(ancestorId);
            }
            this.emit('expansionChange', 'path');
        },

        /**
         * Reset state to initial values
         */
        reset() {
            state.manifest = null;
            state.timeline = null;
            state.nodes = null;
            state.diff = null;
            state.actions = null;
            state.impact = null;
            state.drift = null;
            state.driftTrend = null;
            state.ui.selectedNodeId = null;
            state.ui.expandedNodes.clear();
            state.ui.changedOnlyMode = false;
            state.ui.searchQuery = '';
            state.derived.nodeIndex.clear();
            state.derived.parentIndex.clear();
            state.derived.changedNodes.clear();
            this.emit('reset');
        }
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AppState;
}
