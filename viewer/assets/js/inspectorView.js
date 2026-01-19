/**
 * SimTreeNav Inspector View
 * Node detail panel with before/after, links, fingerprints, and explain surfaces
 */

const InspectorView = (function() {
    'use strict';

    // DOM references
    let container = null;
    let currentNodeId = null;

    /**
     * Initialize the inspector view
     */
    function init(containerElement) {
        container = containerElement;
        container.innerHTML = `
            <div class="inspector-empty">
                <p>Select a node to inspect</p>
            </div>
        `;

        // State subscriptions
        AppState.on('selectionChange', (nodeId) => {
            currentNodeId = nodeId;
            render();
        });

        AppState.on('nodeClicked', (nodeId) => {
            currentNodeId = nodeId;
            render();
        });

        AppState.on('actionClicked', (nodeId) => {
            currentNodeId = nodeId;
            render();
        });

        AppState.on('diffClicked', (nodeId) => {
            currentNodeId = nodeId;
            render();
        });

        return { container };
    }

    /**
     * Render inspector for selected node
     */
    function render() {
        if (!currentNodeId) {
            container.innerHTML = `
                <div class="inspector-empty">
                    <p>Select a node to inspect</p>
                </div>
            `;
            return;
        }

        const node = AppState.getNode(currentNodeId);
        if (!node) {
            container.innerHTML = `
                <div class="inspector-empty">
                    <p>Node not found: ${currentNodeId}</p>
                </div>
            `;
            return;
        }

        container.innerHTML = `
            <div class="inspector-header">
                <h3 class="inspector-title">${node.name || node.caption || 'Unnamed'}</h3>
                <div class="inspector-actions">
                    <button class="inspector-btn" data-action="copy-path" title="Copy path">📋</button>
                    <button class="inspector-btn" data-action="copy-id" title="Copy ID">🔗</button>
                    <button class="inspector-btn" data-action="export" title="Export subtree">💾</button>
                </div>
            </div>
            
            <div class="inspector-panels">
                ${renderIdentityPanel(node)}
                ${renderPropertiesPanel(node)}
                ${renderDriftPanel(node)}
                ${renderImpactPanel(node)}
                ${renderLinksPanel(node)}
            </div>
        `;

        // Add event listeners
        container.querySelectorAll('[data-action]').forEach(btn => {
            btn.addEventListener('click', handleAction);
        });
    }

    /**
     * Render identity panel (logicalId, matchConfidence, etc.)
     */
    function renderIdentityPanel(node) {
        return `
            <details class="inspector-panel" open>
                <summary>Identity</summary>
                <div class="inspector-panel-content">
                    <dl class="inspector-dl">
                        <dt>Node ID</dt>
                        <dd><code>${node.id}</code></dd>
                        
                        ${node.logicalId ? `
                            <dt>Logical ID</dt>
                            <dd><code>${node.logicalId}</code></dd>
                        ` : ''}
                        
                        ${node.externalId ? `
                            <dt>External ID</dt>
                            <dd><code>${node.externalId}</code></dd>
                        ` : ''}
                        
                        ${node.path ? `
                            <dt>Path</dt>
                            <dd class="inspector-path">${node.path}</dd>
                        ` : ''}
                        
                        ${node.matchConfidence !== undefined ? `
                            <dt>Match Confidence</dt>
                            <dd>
                                <span class="confidence-badge ${getConfidenceClass(node.matchConfidence)}">
                                    ${(node.matchConfidence * 100).toFixed(1)}%
                                </span>
                            </dd>
                        ` : ''}
                        
                        ${node.matchReason ? `
                            <dt>Match Reason</dt>
                            <dd class="inspector-reason">${node.matchReason}</dd>
                        ` : ''}
                        
                        ${node.fingerprint ? `
                            <dt>Fingerprint</dt>
                            <dd><code class="fingerprint">${node.fingerprint.substring(0, 32)}...</code></dd>
                        ` : ''}
                    </dl>
                </div>
            </details>
        `;
    }

    /**
     * Render properties panel
     */
    function renderPropertiesPanel(node) {
        const excludeKeys = ['id', 'logicalId', 'externalId', 'path', 'children', 'parent', 
                            'matchConfidence', 'matchReason', 'fingerprint', 'driftScore',
                            'pairingConfidence', 'pairingReason', 'riskScore'];

        const properties = Object.entries(node)
            .filter(([key]) => !excludeKeys.includes(key) && !key.startsWith('_'))
            .filter(([, value]) => value !== null && value !== undefined && value !== '');

        if (properties.length === 0) return '';

        return `
            <details class="inspector-panel">
                <summary>Properties (${properties.length})</summary>
                <div class="inspector-panel-content">
                    <dl class="inspector-dl">
                        ${properties.map(([key, value]) => `
                            <dt>${formatKey(key)}</dt>
                            <dd>${formatPropertyValue(value)}</dd>
                        `).join('')}
                    </dl>
                </div>
            </details>
        `;
    }

    /**
     * Render drift pairing panel
     */
    function renderDriftPanel(node) {
        const hasDrift = node.driftScore !== undefined || 
                        node.pairingConfidence !== undefined ||
                        node.deltas;

        if (!hasDrift) return '';

        return `
            <details class="inspector-panel">
                <summary>Drift Pairing</summary>
                <div class="inspector-panel-content">
                    <dl class="inspector-dl">
                        ${node.driftScore !== undefined ? `
                            <dt>Drift Score</dt>
                            <dd>
                                <span class="drift-score ${getDriftClass(node.driftScore)}">
                                    ${node.driftScore.toFixed(2)}
                                </span>
                            </dd>
                        ` : ''}
                        
                        ${node.pairingConfidence !== undefined ? `
                            <dt>Pairing Confidence</dt>
                            <dd>
                                <span class="confidence-badge ${getConfidenceClass(node.pairingConfidence)}">
                                    ${(node.pairingConfidence * 100).toFixed(1)}%
                                </span>
                            </dd>
                        ` : ''}
                        
                        ${node.pairingReason ? `
                            <dt>Pairing Reason</dt>
                            <dd class="inspector-reason">${node.pairingReason}</dd>
                        ` : ''}
                    </dl>
                    
                    ${node.deltas ? renderDeltas(node.deltas) : ''}
                </div>
            </details>
        `;
    }

    /**
     * Render deltas (before/after values)
     */
    function renderDeltas(deltas) {
        if (!deltas || deltas.length === 0) return '';

        return `
            <div class="inspector-deltas">
                <h5>Changes</h5>
                <table class="delta-table">
                    <thead>
                        <tr>
                            <th>Field</th>
                            <th>Before</th>
                            <th>After</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${deltas.map(delta => `
                            <tr>
                                <td>${delta.field}</td>
                                <td class="delta-before">${formatPropertyValue(delta.before)}</td>
                                <td class="delta-after">${formatPropertyValue(delta.after)}</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            </div>
        `;
    }

    /**
     * Render impact panel
     */
    function renderImpactPanel(node) {
        if (node.riskScore === undefined && !node.impactReasons) return '';

        return `
            <details class="inspector-panel">
                <summary>Impact Analysis</summary>
                <div class="inspector-panel-content">
                    ${node.riskScore !== undefined ? `
                        <div class="risk-score-display ${getRiskClass(node.riskScore)}">
                            <span class="risk-label">Risk Score</span>
                            <span class="risk-value">${node.riskScore.toFixed(1)}</span>
                        </div>
                    ` : ''}
                    
                    ${node.impactReasons ? `
                        <div class="impact-reasons">
                            <h5>Risk Factors</h5>
                            <ul>
                                ${node.impactReasons.map(reason => `
                                    <li class="impact-reason">
                                        <span class="reason-weight">${reason.weight?.toFixed(1) || '?'}</span>
                                        <span class="reason-text">${reason.text || reason}</span>
                                    </li>
                                `).join('')}
                            </ul>
                        </div>
                    ` : ''}
                    
                    ${node.evidenceLinks ? `
                        <div class="evidence-links">
                            <h5>Evidence</h5>
                            ${node.evidenceLinks.map(link => `
                                <a href="#" class="evidence-link" data-event-id="${link.eventId}">
                                    ${link.type}: ${link.label}
                                </a>
                            `).join('')}
                        </div>
                    ` : ''}
                </div>
            </details>
        `;
    }

    /**
     * Render links panel (related nodes, references)
     */
    function renderLinksPanel(node) {
        const hasLinks = node.references || node.referencedBy || node.relatedNodes;
        if (!hasLinks) return '';

        return `
            <details class="inspector-panel">
                <summary>Links</summary>
                <div class="inspector-panel-content">
                    ${node.references ? `
                        <div class="link-section">
                            <h5>References (${node.references.length})</h5>
                            <ul class="link-list">
                                ${node.references.slice(0, 10).map(ref => `
                                    <li><a href="#" data-node-id="${ref.id}">${ref.name || ref.id}</a></li>
                                `).join('')}
                                ${node.references.length > 10 ? `<li>...and ${node.references.length - 10} more</li>` : ''}
                            </ul>
                        </div>
                    ` : ''}
                    
                    ${node.referencedBy ? `
                        <div class="link-section">
                            <h5>Referenced By (${node.referencedBy.length})</h5>
                            <ul class="link-list">
                                ${node.referencedBy.slice(0, 10).map(ref => `
                                    <li><a href="#" data-node-id="${ref.id}">${ref.name || ref.id}</a></li>
                                `).join('')}
                                ${node.referencedBy.length > 10 ? `<li>...and ${node.referencedBy.length - 10} more</li>` : ''}
                            </ul>
                        </div>
                    ` : ''}
                </div>
            </details>
        `;
    }

    /**
     * Handle action button clicks
     */
    function handleAction(event) {
        const action = event.target.dataset.action;
        const node = AppState.getNode(currentNodeId);
        if (!node) return;

        switch (action) {
            case 'copy-path':
                copyToClipboard(node.path || buildPath(node));
                showToast('Path copied to clipboard');
                break;

            case 'copy-id':
                copyToClipboard(node.logicalId || node.id);
                showToast('ID copied to clipboard');
                break;

            case 'export':
                exportSubtree(node);
                break;
        }
    }

    /**
     * Build path for node
     */
    function buildPath(node) {
        const parts = [];
        let current = node;
        while (current) {
            parts.unshift(current.name || current.caption || current.id);
            const parentId = AppState.getParentId(current.id);
            current = parentId ? AppState.getNode(parentId) : null;
        }
        return parts.join(' / ');
    }

    /**
     * Copy text to clipboard
     */
    async function copyToClipboard(text) {
        try {
            await navigator.clipboard.writeText(text);
        } catch (e) {
            // Fallback for older browsers
            const textArea = document.createElement('textarea');
            textArea.value = text;
            document.body.appendChild(textArea);
            textArea.select();
            document.execCommand('copy');
            document.body.removeChild(textArea);
        }
    }

    /**
     * Export subtree as JSON
     */
    function exportSubtree(node) {
        const subtree = collectSubtree(node);
        const json = JSON.stringify(subtree, null, 2);
        const blob = new Blob([json], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        
        const a = document.createElement('a');
        a.href = url;
        a.download = `subtree_${node.id}.json`;
        a.click();
        
        URL.revokeObjectURL(url);
    }

    /**
     * Collect node and all descendants
     */
    function collectSubtree(node) {
        const result = { ...node };
        if (node.children) {
            result.children = node.children.map(child => collectSubtree(child));
        }
        return result;
    }

    /**
     * Show toast notification
     */
    function showToast(message) {
        let toast = document.querySelector('.inspector-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.className = 'inspector-toast';
            document.body.appendChild(toast);
        }
        toast.textContent = message;
        toast.classList.add('show');
        setTimeout(() => toast.classList.remove('show'), 2000);
    }

    /**
     * Format property key for display
     */
    function formatKey(key) {
        return key
            .replace(/([A-Z])/g, ' $1')
            .replace(/^./, str => str.toUpperCase())
            .replace(/_/g, ' ');
    }

    /**
     * Format property value for display
     */
    function formatPropertyValue(value) {
        if (value === null) return '<em>null</em>';
        if (value === undefined) return '<em>undefined</em>';
        if (Array.isArray(value)) {
            if (value.length === 0) return '<em>[]</em>';
            if (value.length > 5) return `Array(${value.length})`;
            return value.map(v => formatPropertyValue(v)).join(', ');
        }
        if (typeof value === 'object') {
            return `<code>${JSON.stringify(value)}</code>`;
        }
        if (typeof value === 'boolean') {
            return value ? '✓ true' : '✗ false';
        }
        return String(value);
    }

    /**
     * Get confidence class based on value
     */
    function getConfidenceClass(confidence) {
        if (confidence >= 0.9) return 'high';
        if (confidence >= 0.7) return 'medium';
        return 'low';
    }

    /**
     * Get drift class based on score
     */
    function getDriftClass(score) {
        if (score < 0.1) return 'low';
        if (score < 0.3) return 'medium';
        return 'high';
    }

    /**
     * Get risk class based on score
     */
    function getRiskClass(score) {
        if (score < 3) return 'low';
        if (score < 7) return 'medium';
        return 'high';
    }

    // Public API
    return {
        init,
        render,
        showNode(nodeId) {
            currentNodeId = nodeId;
            render();
        }
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = InspectorView;
}
