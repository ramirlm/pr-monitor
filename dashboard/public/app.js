// ==================================
// PR Monitor Dashboard - Frontend
// ==================================

const API_BASE = 'http://localhost:3000/api';

// Global state
let currentLogPR = null;
let logRefreshInterval = null;

// ==================================
// Initialization
// ==================================

document.addEventListener('DOMContentLoaded', () => {
    console.log('Dashboard initializing...');

    // Initialize tabs
    initTabs();

    // Load initial data
    loadStats();
    loadDetectedPR();
    loadMonitors();
    loadPRs();

    // Setup log viewer
    setupLogViewer();

    // Auto-refresh every 30 seconds
    setInterval(() => {
        loadStats();
        const activeTab = document.querySelector('.tab-button.active')?.getAttribute('data-tab');
        if (activeTab === 'monitors') {
            loadMonitors();
        } else if (activeTab === 'prs') {
            loadPRs();
        }
    }, 30000);

    console.log('Dashboard initialized');
});

// ==================================
// Tab Management
// ==================================

function initTabs() {
    const tabButtons = document.querySelectorAll('.tab-button');
    tabButtons.forEach(button => {
        button.addEventListener('click', () => {
            const tabName = button.getAttribute('data-tab');
            if (!tabName) return;

            // Update active states
            document.querySelectorAll('.tab-button').forEach(b => b.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));

            button.classList.add('active');
            document.getElementById(`${tabName}-tab`)?.classList.add('active');

            // Load data for active tab
            if (tabName === 'monitors') {
                loadMonitors();
            } else if (tabName === 'prs') {
                loadPRs();
            }
        });
    });
}

// ==================================
// Stats Loading
// ==================================

async function loadStats() {
    try {
        const [statsResponse, monitorsResponse] = await Promise.all([
            fetch(`${API_BASE}/stats`),
            fetch(`${API_BASE}/monitors`)
        ]);

        const statsData = await statsResponse.json();
        const monitorsData = await monitorsResponse.json();

        if (statsData.success) {
            document.getElementById('total-prs').textContent = statsData.stats.total_prs.count.toString();
            document.getElementById('open-prs').textContent = statsData.stats.open_prs.count.toString();
            document.getElementById('unaddressed-comments').textContent = statsData.stats.unaddressed_comments.count.toString();
        }

        if (monitorsData.success) {
            document.getElementById('running-monitors').textContent = monitorsData.monitors.length.toString();
        }
    } catch (error) {
        console.error('Failed to load stats:', error);
    }
}

// ==================================
// Detected PR Banner
// ==================================

async function loadDetectedPR() {
    try {
        const response = await fetch(`${API_BASE}/detect-pr`);
        const data = await response.json();

        if (data.success && data.pr) {
            // Check if this PR is already being monitored
            const monitorsResponse = await fetch(`${API_BASE}/monitors`);
            const monitorsData = await monitorsResponse.json();

            const isMonitored = monitorsData.success &&
                monitorsData.monitors.some(m => m.pr_number === data.pr.number);

            showDetectedPRBanner(data.pr, data.branch, isMonitored);
        }
    } catch (error) {
        console.error('Failed to detect PR:', error);
    }
}

function showDetectedPRBanner(pr, branch, isMonitored = false) {
    const banner = document.getElementById('detected-pr-banner');
    if (!banner) return;

    const buttonHtml = isMonitored
        ? `<button class="btn btn-success" disabled>✅ Already Monitoring</button>`
        : `<button class="btn btn-primary" onclick="startMonitoring(${pr.number})">🚀 Start Monitoring</button>`;

    banner.innerHTML = `
    <div class="detected-pr-content">
      <div>
        <strong>📍 Detected PR:</strong> #${pr.number} - ${pr.title}
        <br><small>Branch: ${branch}</small>
      </div>
      ${buttonHtml}
    </div>
  `;
    banner.style.display = 'block';
}

// ==================================
// Monitor Management
// ==================================

async function loadMonitors() {
    const container = document.getElementById('monitors-list');
    if (!container) return;

    container.innerHTML = '<div class="loading">Loading monitors...</div>';

    try {
        const response = await fetch(`${API_BASE}/monitors`);
        const data = await response.json();

        if (data.success) {
            if (data.monitors.length === 0) {
                container.innerHTML = '<div class="empty-state">No monitors currently running</div>';
                // Update log selector
                updateLogSelector([]);
                return;
            }

            container.innerHTML = data.monitors.map(monitor => `
        <div class="monitor-card">
          <div class="monitor-header">
            <div class="monitor-title">
              PR #${monitor.pr_number} - ${monitor.repo}
            </div>
            <button class="btn btn-danger" onclick="stopMonitor(${monitor.pid})">
              🛑 Stop Monitor
            </button>
          </div>
          <div class="monitor-info">
            <div class="info-item">
              <span class="info-label">PID</span>
              <span class="info-value">${monitor.pid}</span>
            </div>
            <div class="info-item">
              <span class="info-label">CPU</span>
              <span class="info-value">${monitor.cpu}%</span>
            </div>
            <div class="info-item">
              <span class="info-label">Memory</span>
              <span class="info-value">${monitor.mem}%</span>
            </div>
            <div class="info-item">
              <span class="info-label">Running Time</span>
              <span class="info-value">${monitor.time}</span>
            </div>
          </div>
        </div>
      `).join('');

            // Update log selector with running monitors
            updateLogSelector(data.monitors);
        } else {
            container.innerHTML = '<div class="empty-state">Failed to load monitors</div>';
        }
    } catch (error) {
        console.error('Failed to load monitors:', error);
        container.innerHTML = `<div class="empty-state">Error loading monitors: ${error.message}</div>`;
    }
}

async function startMonitoring(prNumber) {
    try {
        const response = await fetch(`${API_BASE}/monitors/start`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ pr_number: prNumber })
        });

        const data = await response.json();

        if (data.success) {
            alert(`✅ Monitor started for PR #${prNumber}`);
            loadMonitors();
            loadDetectedPR();
        } else {
            alert(`❌ Failed to start monitor: ${data.error}`);
        }
    } catch (error) {
        console.error('Failed to start monitor:', error);
        alert(`❌ Error: ${error.message}`);
    }
}

async function stopMonitor(pid) {
    if (!confirm('Are you sure you want to stop this monitor?')) return;

    try {
        const response = await fetch(`${API_BASE}/monitors/${pid}/stop`, {
            method: 'POST'
        });

        const data = await response.json();

        if (data.success) {
            alert('✅ Monitor stopped');
            loadMonitors();
        } else {
            alert(`❌ Failed to stop monitor: ${data.error}`);
        }
    } catch (error) {
        console.error('Failed to stop monitor:', error);
        alert(`❌ Error: ${error.message}`);
    }
}

function refreshMonitors() {
    loadMonitors();
}

// ==================================
// PR List Management
// ==================================

async function loadPRs() {
    const container = document.getElementById('prs-list');
    if (!container) return;

    container.innerHTML = '<div class="loading">Loading PRs...</div>';

    try {
        const response = await fetch(`${API_BASE}/prs`);
        const data = await response.json();

        if (data.success) {
            if (data.prs.length === 0) {
                container.innerHTML = '<div class="empty-state">No PRs tracked yet</div>';
                return;
            }

            container.innerHTML = data.prs.map(pr => renderPRCard(pr)).join('');
        } else {
            container.innerHTML = '<div class="empty-state">Failed to load PRs</div>';
        }
    } catch (error) {
        console.error('Failed to load PRs:', error);
        container.innerHTML = `<div class="empty-state">Error loading PRs: ${error.message}</div>`;
    }
}

function renderPRCard(pr) {
    const stateClass = pr.state === 'open' ? 'state-open' : 'state-closed';
    const unaddressedBadge = pr.unaddressed_comments > 0
        ? `<span class="badge badge-warning">${pr.unaddressed_comments} unaddressed</span>`
        : '';

    // Workflow status badge
    let workflowBadge = '';
    if (pr.failed_workflow_count > 0) {
        workflowBadge = `<span class="badge badge-danger">❌ ${pr.failed_workflow_count} workflow${pr.failed_workflow_count > 1 ? 's' : ''} failed</span>`;
    } else if (pr.workflow_count > 0) {
        workflowBadge = `<span class="badge badge-success">✅ All workflows passed</span>`;
    }

    return `
    <div class="pr-card" onclick="showPRDetail(${pr.pr_number})">
      <div class="pr-header">
        <div class="pr-title">
          PR #${pr.pr_number} - ${pr.title}
        </div>
        <span class="pr-state ${stateClass}">${pr.state.toUpperCase()}</span>
      </div>
      <div class="pr-meta">
        <div class="meta-item">
          <strong>Repository:</strong> ${pr.repo}
        </div>
        <div class="meta-item">
          <strong>Author:</strong> ${pr.author}
        </div>
        <div class="meta-item">
          <strong>Comments:</strong> ${pr.comment_count} ${unaddressedBadge}
        </div>
        <div class="meta-item">
          <strong>Workflows:</strong> ${pr.workflow_count} ${workflowBadge}
        </div>
        <div class="meta-item">
          <strong>Last Updated:</strong> ${formatDate(pr.updated_at)}
        </div>
      </div>
    </div>
  `;
}

function refreshPRs() {
    loadPRs();
}

// ==================================
// PR Detail Modal
// ==================================

async function showPRDetail(prNumber) {
    const modal = document.getElementById('pr-modal');
    const modalBody = document.getElementById('modal-body');
    const modalTitle = document.getElementById('modal-title');

    if (!modal || !modalBody || !modalTitle) return;

    modalTitle.textContent = `PR #${prNumber} Details`;
    modalBody.innerHTML = '<div class="loading">Loading...</div>';
    modal.style.display = 'block';

    try {
        const [prResponse, workflowsResponse, commentsResponse] = await Promise.all([
            fetch(`${API_BASE}/prs/${prNumber}`),
            fetch(`${API_BASE}/prs/${prNumber}/workflows`),
            fetch(`${API_BASE}/prs/${prNumber}/comments`)
        ]);

        const prData = await prResponse.json();
        const workflowsData = await workflowsResponse.json();
        const commentsData = await commentsResponse.json();

        if (prData.success && workflowsData.success && commentsData.success) {
            modalBody.innerHTML = renderPRDetail(prData.pr, workflowsData.workflows, commentsData.comments);
        } else {
            modalBody.innerHTML = '<div class="error">Failed to load PR details</div>';
        }
    } catch (error) {
        console.error('Failed to load PR details:', error);
        modalBody.innerHTML = `<div class="error">Error: ${error.message}</div>`;
    }
}

function renderPRDetail(pr, workflows, comments) {
    const failedWorkflows = workflows.filter(w => w.conclusion === 'failure');

    let failedWorkflowsHtml = '';
    if (failedWorkflows.length > 0) {
        failedWorkflowsHtml = `
      <div class="detail-section">
        <h3 style="color: #e74c3c;">❌ Failed Workflows (${failedWorkflows.length})</h3>
        ${failedWorkflows.map(w => renderFailedWorkflow(w)).join('')}
      </div>
    `;
    }

    const unaddressedComments = comments.filter(c => !c.addressed);
    let commentsHtml = '';
    if (unaddressedComments.length > 0) {
        commentsHtml = `
      <div class="detail-section">
        <h3>💬 Unaddressed Comments (${unaddressedComments.length})</h3>
        ${unaddressedComments.map(c => renderComment(c)).join('')}
      </div>
    `;
    }

    return `
    <div class="pr-detail">
      <div class="detail-section">
        <h3>📋 PR Information</h3>
        <div class="detail-grid">
          <div><strong>Title:</strong> ${pr.title}</div>
          <div><strong>Author:</strong> ${pr.author}</div>
          <div><strong>State:</strong> ${pr.state}</div>
          <div><strong>Created:</strong> ${formatDate(pr.created_at)}</div>
        </div>
        <div style="margin-top: 1rem;">
          <a href="${pr.url}" target="_blank" class="btn btn-primary">View on GitHub →</a>
        </div>
      </div>

      ${failedWorkflowsHtml}

      <div class="detail-section">
        <h3>🔄 All Workflows (${workflows.length})</h3>
        <div class="workflow-summary">
          ${workflows.map(w => renderWorkflowSummary(w)).join('')}
        </div>
      </div>

      ${commentsHtml}
    </div>
  `;
}

function renderFailedWorkflow(workflow) {
    return `
    <div class="failed-workflow-card" style="background: #ffe6e6; border: 2px solid #e74c3c; border-radius: 8px; padding: 1rem; margin-bottom: 1rem;">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
        <strong style="font-size: 1.1rem;">${workflow.workflow_name}</strong>
        <a href="${workflow.html_url}" target="_blank" class="btn btn-secondary btn-sm">View Run →</a>
      </div>
      <div style="color: #666; margin-bottom: 1rem;">
        <span>Jobs: ${workflow.job_count} total, ${workflow.failed_job_count} failed</span>
        <span style="margin-left: 1rem;">Run #${workflow.run_number}</span>
      </div>
      <div class="failed-jobs">
        <strong style="display: block; margin-bottom: 0.5rem;">Failed Jobs:</strong>
        <div id="workflow-jobs-${workflow.id}">
          <div style="color: #888; font-style: italic;">Loading job details...</div>
        </div>
      </div>
    </div>
  `;
}

async function loadWorkflowJobs(workflowId) {
    try {
        const response = await fetch(`${API_BASE}/workflows/${workflowId}/jobs`);
        const data = await response.json();

        const container = document.getElementById(`workflow-jobs-${workflowId}`);
        if (!container) return;

        if (data.success) {
            const failedJobs = data.jobs.filter(j => j.conclusion === 'failure');

            if (failedJobs.length === 0) {
                container.innerHTML = '<div style="color: #888;">No failed jobs found</div>';
                return;
            }

            container.innerHTML = failedJobs.map(job => {
                const failedSteps = JSON.parse(job.failed_steps || '[]');
                const stepsHtml = failedSteps.map(step => `
            <div style="padding: 0.5rem; background: #fff; border-left: 3px solid #e74c3c; margin-bottom: 0.25rem;">
              <strong>Step ${step.number}:</strong> ${step.name}
            </div>
          `).join('');

                return `
          <div style="background: #fff5f5; border: 1px solid #e74c3c; border-radius: 4px; padding: 0.75rem; margin-bottom: 0.5rem;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
              <strong>${job.job_name}</strong>
              <a href="${job.html_url}" target="_blank" style="font-size: 0.85rem; color: #3498db;">View Logs →</a>
            </div>
            <div style="font-size: 0.9rem; color: #e74c3c; margin-bottom: 0.5rem;">
              ⚠️ ${job.error_message}
            </div>
            ${failedSteps.length > 0 ? `<div style="font-size: 0.85rem;">${stepsHtml}</div>` : ''}
          </div>
        `;
            }).join('');

            // Add to workflows that need to load jobs
            setTimeout(() => loadAllWorkflowJobs(), 100);
        }
    } catch (error) {
        console.error('Failed to load workflow jobs:', error);
        const container = document.getElementById(`workflow-jobs-${workflowId}`);
        if (container) {
            container.innerHTML = `<div style="color: #e74c3c;">Error loading jobs: ${error.message}</div>`;
        }
    }
}

function loadAllWorkflowJobs() {
    // Find all workflow job containers and load their jobs
    document.querySelectorAll('[id^="workflow-jobs-"]').forEach(container => {
        const workflowId = container.id.replace('workflow-jobs-', '');
        if (container.textContent.includes('Loading job details...')) {
            loadWorkflowJobs(workflowId);
        }
    });
}

function renderWorkflowSummary(workflow) {
    const statusIcon = workflow.conclusion === 'success' ? '✅' : workflow.conclusion === 'failure' ? '❌' : '⏸️';
    const statusColor = workflow.conclusion === 'success' ? '#27ae60' : workflow.conclusion === 'failure' ? '#e74c3c' : '#95a5a6';

    return `
    <div style="padding: 0.5rem; border-left: 3px solid ${statusColor}; margin-bottom: 0.5rem;">
      ${statusIcon} ${workflow.workflow_name} - ${workflow.conclusion}
    </div>
  `;
}

function renderComment(comment) {
    return `
    <div class="comment-card">
      <div class="comment-header">
        <strong>${comment.author}</strong>
        <span>${formatDate(comment.created_at)}</span>
      </div>
      <div class="comment-body">${comment.body}</div>
      <button class="btn btn-sm btn-success" onclick="markCommentAddressed(${comment.comment_id})">
        ✓ Mark as Addressed
      </button>
    </div>
  `;
}

async function markCommentAddressed(commentId) {
    try {
        const response = await fetch(`${API_BASE}/comments/${commentId}/address`, {
            method: 'POST'
        });

        const data = await response.json();

        if (data.success) {
            // Reload the current PR detail
            const modal = document.getElementById('pr-modal');
            if (modal && modal.style.display === 'block') {
                // Extract PR number from modal title
                const titleElement = document.getElementById('modal-title');
                if (titleElement) {
                    const match = titleElement.textContent.match(/PR #(\d+)/);
                    if (match) {
                        showPRDetail(parseInt(match[1]));
                    }
                }
            }
        } else {
            alert(`Failed to mark comment as addressed: ${data.error}`);
        }
    } catch (error) {
        console.error('Failed to mark comment as addressed:', error);
        alert(`Error: ${error.message}`);
    }
}

function closeModal() {
    const modal = document.getElementById('pr-modal');
    if (modal) {
        modal.style.display = 'none';
    }
}

// Close modal when clicking outside
window.onclick = function(event) {
    const modal = document.getElementById('pr-modal');
    if (event.target === modal) {
        modal.style.display = 'none';
    }
}

// ==================================
// Log Viewer
// ==================================

function setupLogViewer() {
    const select = document.getElementById('log-pr-select');
    const autoRefresh = document.getElementById('log-auto-refresh');

    if (select) {
        select.addEventListener('change', (e) => {
            const prNumber = e.target.value;
            currentLogPR = prNumber ? parseInt(prNumber) : null;

            if (currentLogPR) {
                loadLogs(currentLogPR);
                if (autoRefresh && autoRefresh.checked) {
                    startLogRefresh();
                }
            } else {
                clearLogDisplay();
                stopLogRefresh();
            }
        });
    }

    if (autoRefresh) {
        autoRefresh.addEventListener('change', (e) => {
            if (e.target.checked && currentLogPR) {
                startLogRefresh();
            } else {
                stopLogRefresh();
            }
        });
    }
}

function updateLogSelector(monitors) {
    const select = document.getElementById('log-pr-select');
    if (!select) return;

    const currentValue = select.value;

    if (!monitors || monitors.length === 0) {
        select.innerHTML = '<option value="">No monitors running</option>';
        clearLogDisplay();
        return;
    }

    const options = monitors.map(m =>
        `<option value="${m.pr_number}"${currentValue == m.pr_number ? ' selected' : ''}>PR #${m.pr_number} - ${m.repo}</option>`
    ).join('');

    select.innerHTML = '<option value="">Select a PR to view logs...</option>' + options;

    // If there was a selection and it's still valid, keep it
    if (currentValue && monitors.some(m => m.pr_number == currentValue)) {
        select.value = currentValue;
    }
}

async function loadLogs(prNumber, lines = 100) {
    const display = document.getElementById('log-display');
    const metadata = document.getElementById('log-metadata');

    if (!display) return;

    if (!prNumber) {
        display.innerHTML = '<div style="color: #888;">Select a PR from the dropdown above to view its logs...</div>';
        if (metadata) metadata.style.display = 'none';
        return;
    }

    try {
        const response = await fetch(`${API_BASE}/logs/${prNumber}/tail?lines=${lines}`);
        const data = await response.json();

        if (data.success) {
            if (data.exists) {
                // Color code log levels
                const coloredLogs = data.logs
                    .replace(/\[ERROR\]/g, '<span style="color: #e74c3c; font-weight: bold;">[ERROR]</span>')
                    .replace(/\[WARN\]/g, '<span style="color: #f39c12; font-weight: bold;">[WARN]</span>')
                    .replace(/\[INFO\]/g, '<span style="color: #3498db;">[INFO]</span>')
                    .replace(/\[DEBUG\]/g, '<span style="color: #95a5a6;">[DEBUG]</span>')
                    .replace(/✅/g, '<span style="color: #27ae60;">✅</span>')
                    .replace(/❌/g, '<span style="color: #e74c3c;">❌</span>');

                display.innerHTML = coloredLogs;
                display.scrollTop = display.scrollHeight;

                if (metadata) {
                    metadata.innerHTML = `
            <span style="color: #27ae60;">🟢 Live</span>
            <span>Updated: ${new Date(data.timestamp).toLocaleTimeString()}</span>
          `;
                    metadata.style.display = 'block';
                }
            } else {
                display.innerHTML = `<div style="color: #f39c12;">${data.logs}</div>`;
                if (metadata) metadata.style.display = 'none';
            }
        } else {
            display.innerHTML = `<div style="color: #e74c3c;">Failed to load logs</div>`;
            if (metadata) metadata.style.display = 'none';
        }
    } catch (error) {
        console.error('Failed to load logs:', error);
        display.innerHTML = `<div style="color: #e74c3c;">Failed to load logs: ${error.message}</div>`;
        if (metadata) metadata.style.display = 'none';
    }
}

function startLogRefresh() {
    stopLogRefresh(); // Clear any existing interval

    logRefreshInterval = setInterval(() => {
        if (currentLogPR) {
            loadLogs(currentLogPR);
        }
    }, 3000); // Refresh every 3 seconds
}

function stopLogRefresh() {
    if (logRefreshInterval) {
        clearInterval(logRefreshInterval);
        logRefreshInterval = null;
    }
}

function refreshLogs() {
    const select = document.getElementById('log-pr-select');
    if (select && select.value) {
        loadLogs(parseInt(select.value));
    }
}

function clearLogDisplay() {
    const display = document.getElementById('log-display');
    const metadata = document.getElementById('log-metadata');

    if (display) {
        display.innerHTML = '<div style="color: #888;">Select a PR from the dropdown above to view its logs...</div>';
    }
    if (metadata) {
        metadata.style.display = 'none';
    }
    currentLogPR = null;
    stopLogRefresh();
}

// ==================================
// Utility Functions
// ==================================

function formatDate(dateString) {
    if (!dateString) return 'N/A';
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now - date;
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins} minute${diffMins > 1 ? 's' : ''} ago`;
    if (diffHours < 24) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
    if (diffDays < 7) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;

    return date.toLocaleDateString();
}
