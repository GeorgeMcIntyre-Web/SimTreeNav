/**
 * SimTreeNav Timeline View
 * Timeline selector and activity feed components
 */

const TimelineView = (function() {
    'use strict';

    // DOM references
    let container = null;
    let tabContainer = null;
    let contentContainer = null;
    let currentTab = 'timeline';

    // Play mode state
    let playInterval = null;
    let playIndex = 0;

    /**
     * Initialize the timeline view
     */
    function init(containerElement) {
        container = containerElement;
        container.innerHTML = '';

        // Create tab navigation
        tabContainer = document.createElement('div');
        tabContainer.className = 'timeline-tabs';
        tabContainer.innerHTML = `
            <button class="timeline-tab active" data-tab="timeline">Timeline</button>
            <button class="timeline-tab" data-tab="actions">Actions</button>
            <button class="timeline-tab" data-tab="diffs">Diffs</button>
        `;
        container.appendChild(tabContainer);

        // Create content container
        contentContainer = document.createElement('div');
        contentContainer.className = 'timeline-content';
        container.appendChild(contentContainer);

        // Event listeners
        tabContainer.addEventListener('click', handleTabClick);
        
        // State subscriptions
        AppState.on('dataLoaded', () => render());
        AppState.on('timeline', () => render());
        AppState.on('actions', () => render());
        AppState.on('diff', () => render());

        return { container, tabContainer, contentContainer };
    }

    /**
     * Handle tab clicks
     */
    function handleTabClick(event) {
        const tab = event.target.closest('.timeline-tab');
        if (!tab) return;

        const tabName = tab.dataset.tab;
        if (tabName === currentTab) return;

        currentTab = tabName;

        // Update active tab
        tabContainer.querySelectorAll('.timeline-tab').forEach(t => {
            t.classList.toggle('active', t.dataset.tab === tabName);
        });

        render();
    }

    /**
     * Render current tab content
     */
    function render() {
        switch (currentTab) {
            case 'timeline':
                renderTimeline();
                break;
            case 'actions':
                renderActions();
                break;
            case 'diffs':
                renderDiffs();
                break;
        }
    }

    /**
     * Render timeline tab
     */
    function renderTimeline() {
        const timeline = AppState.get('timeline');
        
        if (!timeline || !timeline.snapshots || timeline.snapshots.length === 0) {
            contentContainer.innerHTML = `
                <div class="timeline-empty">
                    <p>No timeline data available.</p>
                    <p class="timeline-hint">Timeline will show snapshot history when available.</p>
                </div>
            `;
            return;
        }

        const snapshots = timeline.snapshots;
        const currentSnapshot = AppState.get('ui.currentSnapshot');
        const compareSnapshot = AppState.get('ui.compareSnapshot');

        let html = `
            <div class="timeline-controls">
                <div class="timeline-selector">
                    <label>Snapshot:</label>
                    <select id="snapshot-select" class="timeline-select">
                        ${snapshots.map((s, i) => `
                            <option value="${i}" ${i === currentSnapshot ? 'selected' : ''}>
                                ${formatSnapshotLabel(s, i)}
                            </option>
                        `).join('')}
                    </select>
                </div>
                <div class="timeline-compare">
                    <label>Compare with:</label>
                    <select id="compare-select" class="timeline-select">
                        <option value="">None</option>
                        ${snapshots.map((s, i) => `
                            <option value="${i}" ${i === compareSnapshot ? 'selected' : ''}>
                                ${formatSnapshotLabel(s, i)}
                            </option>
                        `).join('')}
                    </select>
                </div>
                <div class="timeline-play-controls">
                    <button id="play-btn" class="timeline-btn" title="Play through snapshots">
                        ${playInterval ? '⏸️ Pause' : '▶️ Play'}
                    </button>
                    <button id="prev-btn" class="timeline-btn" title="Previous snapshot">⏮️</button>
                    <button id="next-btn" class="timeline-btn" title="Next snapshot">⏭️</button>
                </div>
            </div>
            <div class="timeline-visual">
                ${renderTimelineVisual(snapshots, currentSnapshot)}
            </div>
            <div class="timeline-details">
                ${renderSnapshotDetails(snapshots[currentSnapshot || 0])}
            </div>
        `;

        contentContainer.innerHTML = html;

        // Add event listeners
        contentContainer.querySelector('#snapshot-select')?.addEventListener('change', (e) => {
            const index = parseInt(e.target.value);
            AppState.set('ui.currentSnapshot', index);
            render();
        });

        contentContainer.querySelector('#compare-select')?.addEventListener('change', (e) => {
            const value = e.target.value;
            AppState.set('ui.compareSnapshot', value ? parseInt(value) : null);
            render();
        });

        contentContainer.querySelector('#play-btn')?.addEventListener('click', togglePlay);
        contentContainer.querySelector('#prev-btn')?.addEventListener('click', () => navigateSnapshot(-1));
        contentContainer.querySelector('#next-btn')?.addEventListener('click', () => navigateSnapshot(1));
    }

    /**
     * Format snapshot label
     */
    function formatSnapshotLabel(snapshot, index) {
        if (snapshot.timestamp) {
            const date = new Date(snapshot.timestamp);
            return `#${index + 1} - ${date.toLocaleDateString()} ${date.toLocaleTimeString()}`;
        }
        return `Snapshot #${index + 1}`;
    }

    /**
     * Render timeline visual (dots/bars)
     */
    function renderTimelineVisual(snapshots, currentIndex) {
        return `
            <div class="timeline-track">
                ${snapshots.map((s, i) => `
                    <div class="timeline-point ${i === currentIndex ? 'active' : ''}" 
                         data-index="${i}" 
                         title="${formatSnapshotLabel(s, i)}">
                        <span class="timeline-dot"></span>
                        ${s.changes ? `<span class="timeline-change-count">${s.changes}</span>` : ''}
                    </div>
                `).join('')}
            </div>
        `;
    }

    /**
     * Render snapshot details
     */
    function renderSnapshotDetails(snapshot) {
        if (!snapshot) return '<p>No snapshot selected</p>';

        return `
            <div class="snapshot-info">
                <h4>Snapshot Details</h4>
                <dl>
                    <dt>Timestamp</dt>
                    <dd>${snapshot.timestamp ? new Date(snapshot.timestamp).toLocaleString() : 'N/A'}</dd>
                    <dt>Node Count</dt>
                    <dd>${snapshot.nodeCount?.toLocaleString() || 'N/A'}</dd>
                    <dt>Changes</dt>
                    <dd>${snapshot.changes?.toLocaleString() || '0'}</dd>
                    ${snapshot.hash ? `<dt>Hash</dt><dd><code>${snapshot.hash.substring(0, 16)}...</code></dd>` : ''}
                </dl>
            </div>
        `;
    }

    /**
     * Toggle play mode
     */
    function togglePlay() {
        if (playInterval) {
            clearInterval(playInterval);
            playInterval = null;
        } else {
            const timeline = AppState.get('timeline');
            if (!timeline?.snapshots) return;

            playIndex = AppState.get('ui.currentSnapshot') || 0;
            playInterval = setInterval(() => {
                playIndex++;
                if (playIndex >= timeline.snapshots.length) {
                    playIndex = 0;
                }
                AppState.set('ui.currentSnapshot', playIndex);
                render();
            }, 2000);
        }
        render();
    }

    /**
     * Navigate to next/previous snapshot
     */
    function navigateSnapshot(direction) {
        const timeline = AppState.get('timeline');
        if (!timeline?.snapshots) return;

        let current = AppState.get('ui.currentSnapshot') || 0;
        current += direction;

        if (current < 0) current = timeline.snapshots.length - 1;
        if (current >= timeline.snapshots.length) current = 0;

        AppState.set('ui.currentSnapshot', current);
        render();
    }

    /**
     * Render actions tab
     */
    function renderActions() {
        const actions = AppState.get('actions');

        if (!actions || actions.length === 0) {
            contentContainer.innerHTML = `
                <div class="timeline-empty">
                    <p>No actions recorded.</p>
                    <p class="timeline-hint">Actions will appear here when changes are detected.</p>
                </div>
            `;
            return;
        }

        const html = `
            <div class="actions-list">
                ${actions.map(action => renderActionItem(action)).join('')}
            </div>
        `;

        contentContainer.innerHTML = html;

        // Add click handlers
        contentContainer.querySelectorAll('.action-item').forEach(item => {
            item.addEventListener('click', () => {
                const nodeId = item.dataset.nodeId;
                if (nodeId) {
                    AppState.expandToNode(nodeId);
                    AppState.selectNode(nodeId);
                    AppState.emit('actionClicked', nodeId);
                }
            });
        });
    }

    /**
     * Render single action item
     */
    function renderActionItem(action) {
        const typeIcons = {
            'add': '➕',
            'remove': '➖',
            'modify': '✏️',
            'move': '↔️',
            'rename': '📝'
        };

        const icon = typeIcons[action.type] || '🔹';
        const nodeId = action.nodeId || action.targetId;

        return `
            <div class="action-item" data-node-id="${nodeId}">
                <span class="action-icon">${icon}</span>
                <span class="action-type">${action.type}</span>
                <span class="action-target">${action.nodeName || action.path || nodeId}</span>
                ${action.timestamp ? `<span class="action-time">${formatTime(action.timestamp)}</span>` : ''}
            </div>
        `;
    }

    /**
     * Render diffs tab
     */
    function renderDiffs() {
        const diff = AppState.get('diff');

        if (!diff || !diff.changes || diff.changes.length === 0) {
            contentContainer.innerHTML = `
                <div class="timeline-empty">
                    <p>No differences found.</p>
                    <p class="timeline-hint">Select two snapshots to compare, or diffs will appear when available.</p>
                </div>
            `;
            return;
        }

        const grouped = groupDiffsByType(diff.changes);

        const html = `
            <div class="diff-summary">
                <span class="diff-stat added">+${grouped.added?.length || 0} added</span>
                <span class="diff-stat removed">-${grouped.removed?.length || 0} removed</span>
                <span class="diff-stat modified">~${grouped.modified?.length || 0} modified</span>
            </div>
            <div class="diff-list">
                ${diff.changes.map(change => renderDiffItem(change)).join('')}
            </div>
        `;

        contentContainer.innerHTML = html;

        // Add click handlers
        contentContainer.querySelectorAll('.diff-item').forEach(item => {
            item.addEventListener('click', () => {
                const nodeId = item.dataset.nodeId;
                if (nodeId) {
                    AppState.expandToNode(nodeId);
                    AppState.selectNode(nodeId);
                    AppState.emit('diffClicked', nodeId);
                }
            });
        });
    }

    /**
     * Group diffs by type
     */
    function groupDiffsByType(changes) {
        const groups = {};
        for (const change of changes) {
            const type = change.type || 'modified';
            if (!groups[type]) groups[type] = [];
            groups[type].push(change);
        }
        return groups;
    }

    /**
     * Render single diff item
     */
    function renderDiffItem(change) {
        const typeClasses = {
            'added': 'diff-added',
            'removed': 'diff-removed',
            'modified': 'diff-modified'
        };

        const typeClass = typeClasses[change.type] || 'diff-modified';

        return `
            <div class="diff-item ${typeClass}" data-node-id="${change.nodeId}">
                <span class="diff-indicator"></span>
                <span class="diff-path">${change.path || change.nodeName || change.nodeId}</span>
                ${change.field ? `<span class="diff-field">${change.field}</span>` : ''}
                ${change.before !== undefined ? `<span class="diff-before">${formatValue(change.before)}</span>` : ''}
                ${change.after !== undefined ? `<span class="diff-after">${formatValue(change.after)}</span>` : ''}
            </div>
        `;
    }

    /**
     * Format timestamp
     */
    function formatTime(timestamp) {
        const date = new Date(timestamp);
        return date.toLocaleTimeString();
    }

    /**
     * Format value for display
     */
    function formatValue(value) {
        if (value === null) return 'null';
        if (value === undefined) return 'undefined';
        if (typeof value === 'object') return JSON.stringify(value);
        return String(value);
    }

    /**
     * Stop play mode
     */
    function stopPlay() {
        if (playInterval) {
            clearInterval(playInterval);
            playInterval = null;
        }
    }

    // Public API
    return {
        init,
        render,
        stopPlay,
        setTab(tab) {
            currentTab = tab;
            render();
        }
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = TimelineView;
}
