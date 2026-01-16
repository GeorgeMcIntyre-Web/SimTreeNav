/**
 * SimTreeNav Tree View
 * Virtualized tree rendering with efficient DOM updates
 */

const TreeView = (function() {
    'use strict';

    // Constants
    const ROW_HEIGHT = 28;
    const BUFFER_SIZE = 10;
    const INDENT_WIDTH = 20;

    // DOM references
    let container = null;
    let scrollContainer = null;
    let viewport = null;
    let heightSpacer = null;

    // Virtualization state
    let flattenedNodes = [];
    let visibleStart = 0;
    let visibleEnd = 0;
    let renderedRows = new Map();

    /**
     * Initialize the tree view
     */
    function init(containerElement) {
        container = containerElement;
        
        // Create scroll container
        scrollContainer = document.createElement('div');
        scrollContainer.className = 'tree-scroll-container';
        scrollContainer.style.cssText = 'height: 100%; overflow-y: auto; position: relative;';
        
        // Create height spacer for virtual scrolling
        heightSpacer = document.createElement('div');
        heightSpacer.className = 'tree-height-spacer';
        heightSpacer.style.cssText = 'position: absolute; top: 0; left: 0; right: 0; pointer-events: none;';
        
        // Create viewport for visible rows
        viewport = document.createElement('div');
        viewport.className = 'tree-viewport';
        viewport.style.cssText = 'position: relative; will-change: transform;';
        
        scrollContainer.appendChild(heightSpacer);
        scrollContainer.appendChild(viewport);
        container.appendChild(scrollContainer);
        
        // Event listeners
        scrollContainer.addEventListener('scroll', handleScroll);
        viewport.addEventListener('click', handleClick);
        
        // State subscriptions
        AppState.on('nodes', () => rebuildFlattenedList());
        AppState.on('expansionChange', () => rebuildFlattenedList());
        AppState.on('filterChange', () => rebuildFlattenedList());
        AppState.on('searchChange', () => rebuildFlattenedList());
        AppState.on('selectionChange', handleSelectionChange);
        
        return { container, scrollContainer, viewport };
    }

    /**
     * Flatten tree structure for virtualization
     */
    function flattenTree(nodes, depth = 0, visible = true) {
        const result = [];
        if (!nodes) return result;

        const changedOnlyMode = AppState.get('ui.changedOnlyMode');
        const searchQuery = AppState.get('ui.searchQuery')?.toLowerCase() || '';
        const changedNodes = AppState.get('derived.changedNodes');

        for (const node of nodes) {
            if (!visible) continue;

            // Apply filters
            let matchesSearch = true;
            if (searchQuery) {
                const name = (node.name || node.caption || '').toLowerCase();
                const path = (node.path || '').toLowerCase();
                const id = String(node.id || '');
                matchesSearch = name.includes(searchQuery) || 
                               path.includes(searchQuery) || 
                               id.includes(searchQuery);
            }

            let matchesChangedOnly = true;
            if (changedOnlyMode && changedNodes) {
                // Show if node is changed OR has changed descendants
                matchesChangedOnly = isNodeOrDescendantChanged(node, changedNodes);
            }

            if (!matchesSearch && !hasMatchingDescendant(node, searchQuery)) {
                continue;
            }

            if (!matchesChangedOnly) {
                continue;
            }

            const isExpanded = AppState.isExpanded(node.id);
            const hasChildren = node.children && node.children.length > 0;

            result.push({
                node,
                depth,
                isExpanded,
                hasChildren,
                isChanged: changedNodes?.has(node.id) || false
            });

            if (hasChildren && isExpanded) {
                result.push(...flattenTree(node.children, depth + 1, true));
            }
        }

        return result;
    }

    /**
     * Check if node or any descendant is changed
     */
    function isNodeOrDescendantChanged(node, changedNodes) {
        if (changedNodes.has(node.id)) return true;
        if (!node.children) return false;
        return node.children.some(child => isNodeOrDescendantChanged(child, changedNodes));
    }

    /**
     * Check if node has matching descendant for search
     */
    function hasMatchingDescendant(node, searchQuery) {
        if (!searchQuery || !node.children) return false;
        
        for (const child of node.children) {
            const name = (child.name || child.caption || '').toLowerCase();
            if (name.includes(searchQuery)) return true;
            if (hasMatchingDescendant(child, searchQuery)) return true;
        }
        return false;
    }

    /**
     * Rebuild flattened list from current state
     */
    function rebuildFlattenedList() {
        const nodes = AppState.get('nodes');
        if (!nodes) {
            flattenedNodes = [];
            render();
            return;
        }

        // Handle both array and object with root
        const nodeArray = Array.isArray(nodes) ? nodes : (nodes.root ? [nodes.root] : []);
        flattenedNodes = flattenTree(nodeArray);

        // Update height spacer
        heightSpacer.style.height = `${flattenedNodes.length * ROW_HEIGHT}px`;

        // Check max nodes warning
        const maxNodes = AppState.get('config.maxNodesInViewer');
        if (flattenedNodes.length > maxNodes) {
            showWarningBanner(`Large dataset: ${flattenedNodes.length.toLocaleString()} nodes. UI is showing first ${maxNodes.toLocaleString()} for performance.`);
            flattenedNodes = flattenedNodes.slice(0, maxNodes);
        } else {
            hideWarningBanner();
        }

        render();
        AppState.emit('treeRebuilt', flattenedNodes.length);
    }

    /**
     * Handle scroll events for virtualization
     */
    function handleScroll() {
        requestAnimationFrame(render);
    }

    /**
     * Render visible rows
     */
    function render() {
        if (!scrollContainer || !viewport) return;

        const scrollTop = scrollContainer.scrollTop;
        const viewportHeight = scrollContainer.clientHeight;

        visibleStart = Math.max(0, Math.floor(scrollTop / ROW_HEIGHT) - BUFFER_SIZE);
        visibleEnd = Math.min(
            flattenedNodes.length,
            Math.ceil((scrollTop + viewportHeight) / ROW_HEIGHT) + BUFFER_SIZE
        );

        // Position viewport
        viewport.style.transform = `translateY(${visibleStart * ROW_HEIGHT}px)`;

        // Track which rows need to be rendered
        const neededRows = new Set();
        for (let i = visibleStart; i < visibleEnd; i++) {
            neededRows.add(i);
        }

        // Remove rows no longer visible
        for (const [index, row] of renderedRows) {
            if (!neededRows.has(index)) {
                row.remove();
                renderedRows.delete(index);
            }
        }

        // Add new rows
        const fragment = document.createDocumentFragment();
        for (let i = visibleStart; i < visibleEnd; i++) {
            if (!renderedRows.has(i)) {
                const row = createRow(flattenedNodes[i], i);
                fragment.appendChild(row);
                renderedRows.set(i, row);
            } else {
                // Update existing row if needed
                updateRow(renderedRows.get(i), flattenedNodes[i]);
            }
        }
        viewport.appendChild(fragment);
    }

    /**
     * Create a tree row element
     */
    function createRow(item, index) {
        const { node, depth, isExpanded, hasChildren, isChanged } = item;
        
        const row = document.createElement('div');
        row.className = 'tree-row';
        row.dataset.nodeId = node.id;
        row.dataset.index = index;
        row.style.cssText = `height: ${ROW_HEIGHT}px; padding-left: ${depth * INDENT_WIDTH}px;`;

        // Selection state
        if (AppState.get('ui.selectedNodeId') === node.id) {
            row.classList.add('selected');
        }

        // Changed state
        if (isChanged) {
            row.classList.add('changed');
        }

        // Toggle button
        const toggle = document.createElement('span');
        toggle.className = 'tree-toggle';
        if (hasChildren) {
            toggle.innerHTML = isExpanded ? '&#9660;' : '&#9654;';
            toggle.dataset.action = 'toggle';
        } else {
            toggle.innerHTML = '&nbsp;';
        }
        row.appendChild(toggle);

        // Icon
        const icon = document.createElement('span');
        icon.className = 'tree-icon';
        icon.innerHTML = getNodeIcon(node);
        row.appendChild(icon);

        // Label
        const label = document.createElement('span');
        label.className = 'tree-label';
        label.textContent = node.name || node.caption || `Node ${node.id}`;
        row.appendChild(label);

        // Node type badge
        if (node.nodeType || node.className) {
            const badge = document.createElement('span');
            badge.className = 'tree-badge';
            badge.textContent = node.nodeType || node.niceName || '';
            row.appendChild(badge);
        }

        return row;
    }

    /**
     * Update existing row
     */
    function updateRow(row, item) {
        const { node } = item;
        const isSelected = AppState.get('ui.selectedNodeId') === node.id;
        
        if (isSelected && !row.classList.contains('selected')) {
            row.classList.add('selected');
        } else if (!isSelected && row.classList.contains('selected')) {
            row.classList.remove('selected');
        }
    }

    /**
     * Get icon for node type
     */
    function getNodeIcon(node) {
        const iconMap = {
            'Project': '📁',
            'Plant': '🏭',
            'Line': '📏',
            'Station': '⚙️',
            'Cell': '🔲',
            'Robot': '🤖',
            'Resource': '🔧',
            'Part': '📦',
            'Assembly': '🔩',
            'Operation': '▶️',
            'Study': '📋',
            'Library': '📚',
            'Folder': '📂',
            'default': '📄'
        };

        const nodeType = node.niceName || node.nodeType || node.className || '';
        for (const [key, icon] of Object.entries(iconMap)) {
            if (nodeType.toLowerCase().includes(key.toLowerCase())) {
                return icon;
            }
        }
        return iconMap.default;
    }

    /**
     * Handle click events on tree
     */
    function handleClick(event) {
        const row = event.target.closest('.tree-row');
        if (!row) return;

        const nodeId = row.dataset.nodeId;
        const action = event.target.dataset.action;

        if (action === 'toggle') {
            AppState.toggleExpand(nodeId);
        } else {
            AppState.selectNode(nodeId);
            AppState.emit('nodeClicked', nodeId);
        }
    }

    /**
     * Handle selection change
     */
    function handleSelectionChange(newId, oldId) {
        // Update old row
        if (oldId) {
            const oldRow = viewport.querySelector(`[data-node-id="${oldId}"]`);
            if (oldRow) oldRow.classList.remove('selected');
        }

        // Update new row
        if (newId) {
            const newRow = viewport.querySelector(`[data-node-id="${newId}"]`);
            if (newRow) {
                newRow.classList.add('selected');
                // Ensure visible
                scrollToNode(newId);
            }
        }
    }

    /**
     * Scroll to make node visible
     */
    function scrollToNode(nodeId) {
        const index = flattenedNodes.findIndex(item => item.node.id === nodeId);
        if (index < 0) return;

        const nodeTop = index * ROW_HEIGHT;
        const nodeBottom = nodeTop + ROW_HEIGHT;
        const scrollTop = scrollContainer.scrollTop;
        const viewportHeight = scrollContainer.clientHeight;

        if (nodeTop < scrollTop) {
            scrollContainer.scrollTop = nodeTop;
        } else if (nodeBottom > scrollTop + viewportHeight) {
            scrollContainer.scrollTop = nodeBottom - viewportHeight;
        }
    }

    /**
     * Navigate to next/previous changed node
     */
    function navigateToChange(direction = 1) {
        const changedNodes = AppState.get('derived.changedNodes');
        if (!changedNodes || changedNodes.size === 0) return;

        const currentId = AppState.get('ui.selectedNodeId');
        const currentIndex = currentId ? 
            flattenedNodes.findIndex(item => item.node.id === currentId) : -1;

        const start = direction > 0 ? currentIndex + 1 : currentIndex - 1;
        const end = direction > 0 ? flattenedNodes.length : -1;

        for (let i = start; i !== end; i += direction) {
            if (i < 0 || i >= flattenedNodes.length) break;
            if (flattenedNodes[i].isChanged) {
                const nodeId = flattenedNodes[i].node.id;
                AppState.expandToNode(nodeId);
                AppState.selectNode(nodeId);
                scrollToNode(nodeId);
                return;
            }
        }
    }

    /**
     * Show warning banner
     */
    function showWarningBanner(message) {
        let banner = container.querySelector('.tree-warning-banner');
        if (!banner) {
            banner = document.createElement('div');
            banner.className = 'tree-warning-banner';
            container.insertBefore(banner, scrollContainer);
        }
        banner.textContent = message;
        banner.style.display = 'block';
    }

    /**
     * Hide warning banner
     */
    function hideWarningBanner() {
        const banner = container.querySelector('.tree-warning-banner');
        if (banner) {
            banner.style.display = 'none';
        }
    }

    /**
     * Get tree statistics
     */
    function getStats() {
        return {
            totalNodes: flattenedNodes.length,
            visibleNodes: visibleEnd - visibleStart,
            renderedNodes: renderedRows.size,
            expandedNodes: AppState.get('ui.expandedNodes').size
        };
    }

    // Public API
    return {
        init,
        rebuildFlattenedList,
        scrollToNode,
        navigateToChange,
        getStats,
        expandAll: () => AppState.expandAll(),
        collapseAll: () => AppState.collapseAll()
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = TreeView;
}
