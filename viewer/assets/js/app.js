/**
 * SimTreeNav Application
 * Main application controller with keyboard shortcuts and coordination
 */

const App = (function() {
    'use strict';

    // Component instances
    let components = {
        tree: null,
        timeline: null,
        inspector: null
    };

    // DOM elements
    let elements = {};

    /**
     * Initialize the application
     */
    async function init() {
        console.log('[SimTreeNav] Initializing v0.6.0...');

        // Get DOM elements
        elements = {
            app: document.getElementById('app'),
            treePanel: document.getElementById('tree-panel'),
            centerPanel: document.getElementById('center-panel'),
            inspectorPanel: document.getElementById('inspector-panel'),
            searchInput: document.getElementById('search-input'),
            changedOnlyToggle: document.getElementById('changed-only-toggle'),
            expandAllBtn: document.getElementById('expand-all-btn'),
            collapseAllBtn: document.getElementById('collapse-all-btn'),
            statsDisplay: document.getElementById('stats-display'),
            loadingOverlay: document.getElementById('loading-overlay')
        };

        // Show loading
        showLoading(true);

        try {
            // Load data
            const success = await DataLoader.init();
            if (!success) {
                showError('Failed to load data. Please check the console for details.');
                return;
            }

            // Initialize components
            // Initialize components with content containers
            const treeContent = document.getElementById('tree-content') || elements.treePanel;
            if (treeContent) {
                components.tree = TreeView.init(treeContent);
            }

            const centerContent = document.getElementById('center-content') || elements.centerPanel;
            if (centerContent) {
                components.timeline = TimelineView.init(centerContent);
            }

            const inspectorContent = document.getElementById('inspector-content') || elements.inspectorPanel;
            if (inspectorContent) {
                components.inspector = InspectorView.init(inspectorContent);
            }

            // Setup event listeners
            setupEventListeners();
            setupKeyboardShortcuts();

            // Initial render
            if (components.tree) {
                TreeView.rebuildFlattenedList();
            }

            updateStats();

            console.log('[SimTreeNav] Initialization complete');

        } catch (error) {
            console.error('[SimTreeNav] Initialization failed:', error);
            showError('Application failed to initialize: ' + error.message);
        } finally {
            showLoading(false);
        }
    }

    /**
     * Setup UI event listeners
     */
    function setupEventListeners() {
        // Search
        if (elements.searchInput) {
            let searchTimeout;
            elements.searchInput.addEventListener('input', (e) => {
                clearTimeout(searchTimeout);
                searchTimeout = setTimeout(() => {
                    AppState.setSearchQuery(e.target.value);
                }, 150);
            });
        }

        // Changed-only toggle
        if (elements.changedOnlyToggle) {
            elements.changedOnlyToggle.addEventListener('change', (e) => {
                AppState.setChangedOnlyMode(e.target.checked);
            });
        }

        // Expand/collapse buttons
        if (elements.expandAllBtn) {
            elements.expandAllBtn.addEventListener('click', () => TreeView.expandAll());
        }

        if (elements.collapseAllBtn) {
            elements.collapseAllBtn.addEventListener('click', () => TreeView.collapseAll());
        }

        // State change listeners
        AppState.on('treeRebuilt', updateStats);
        AppState.on('selectionChange', updateStats);
        AppState.on('expansionChange', updateStats);
    }

    /**
     * Setup keyboard shortcuts
     */
    function setupKeyboardShortcuts() {
        document.addEventListener('keydown', (e) => {
            // Ignore if typing in input
            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
                if (e.key === 'Escape') {
                    e.target.blur();
                }
                return;
            }

            switch (e.key) {
                case '/':
                    // Focus search
                    e.preventDefault();
                    elements.searchInput?.focus();
                    break;

                case 'n':
                    // Next change
                    if (!e.ctrlKey && !e.metaKey) {
                        e.preventDefault();
                        TreeView.navigateToChange(1);
                    }
                    break;

                case 'p':
                    // Previous change
                    if (!e.ctrlKey && !e.metaKey) {
                        e.preventDefault();
                        TreeView.navigateToChange(-1);
                    }
                    break;

                case 'ArrowRight':
                    // Expand selected node
                    e.preventDefault();
                    expandSelectedNode();
                    break;

                case 'ArrowLeft':
                    // Collapse selected node
                    e.preventDefault();
                    collapseSelectedNode();
                    break;

                case 'ArrowDown':
                    // Select next node
                    e.preventDefault();
                    navigateNodes(1);
                    break;

                case 'ArrowUp':
                    // Select previous node
                    e.preventDefault();
                    navigateNodes(-1);
                    break;

                case 'Enter':
                    // Toggle expand on selected
                    e.preventDefault();
                    toggleSelectedNode();
                    break;

                case 'c':
                    // Toggle changed-only mode
                    if (!e.ctrlKey && !e.metaKey) {
                        e.preventDefault();
                        if (elements.changedOnlyToggle) {
                            elements.changedOnlyToggle.checked = !elements.changedOnlyToggle.checked;
                            elements.changedOnlyToggle.dispatchEvent(new Event('change'));
                        }
                    }
                    break;

                case 'Escape':
                    // Clear selection
                    AppState.selectNode(null);
                    break;
            }
        });
    }

    /**
     * Expand selected node
     */
    function expandSelectedNode() {
        const nodeId = AppState.get('ui.selectedNodeId');
        if (nodeId && !AppState.isExpanded(nodeId)) {
            AppState.toggleExpand(nodeId);
        }
    }

    /**
     * Collapse selected node
     */
    function collapseSelectedNode() {
        const nodeId = AppState.get('ui.selectedNodeId');
        if (nodeId && AppState.isExpanded(nodeId)) {
            AppState.toggleExpand(nodeId);
        }
    }

    /**
     * Toggle selected node
     */
    function toggleSelectedNode() {
        const nodeId = AppState.get('ui.selectedNodeId');
        if (nodeId) {
            AppState.toggleExpand(nodeId);
        }
    }

    /**
     * Navigate between nodes
     */
    function navigateNodes(direction) {
        // This would need access to the flattened list from TreeView
        // For now, emit an event that TreeView can handle
        AppState.emit('navigateRequest', direction);
    }

    /**
     * Update statistics display
     */
    function updateStats() {
        if (!elements.statsDisplay) return;

        const stats = TreeView.getStats ? TreeView.getStats() : {};
        const manifest = AppState.get('manifest');

        elements.statsDisplay.innerHTML = `
            <span>Nodes: ${stats.totalNodes?.toLocaleString() || '-'}</span>
            <span>Expanded: ${stats.expandedNodes?.toLocaleString() || '-'}</span>
            ${manifest?.timestamp ? `<span>Updated: ${new Date(manifest.timestamp).toLocaleString()}</span>` : ''}
        `;
    }

    /**
     * Show/hide loading overlay
     */
    function showLoading(show) {
        if (elements.loadingOverlay) {
            elements.loadingOverlay.style.display = show ? 'flex' : 'none';
        }
    }

    /**
     * Show error message
     */
    function showError(message) {
        if (elements.app) {
            elements.app.innerHTML = `
                <div class="error-message">
                    <h2>Error</h2>
                    <p>${message}</p>
                    <button onclick="location.reload()">Reload</button>
                </div>
            `;
        }
    }

    // Public API
    return {
        init,
        getComponents: () => components,
        getElements: () => elements
    };
})();

// Initialize when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => App.init());
} else {
    App.init();
}

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = App;
}
