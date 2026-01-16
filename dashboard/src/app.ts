// API Base URL
const API_BASE = 'http://localhost:3000/api';

// Types
interface Monitor {
  pid: number;
  pr_number: number;
  repo: string;
  cpu: string;
  mem: string;
  time: string;
  command: string;
}

interface PR {
  id: number;
  pr_number: number;
  repo: string;
  title: string;
  state: string;
  author: string;
  created_at: string;
  updated_at: string;
  url: string;
  comment_count: number;
  workflow_count: number;
  failed_workflow_count: number;
  unaddressed_comment_count: number;
}

interface Comment {
  id: number;
  comment_id: number;
  comment_type: string;
  author: string;
  body: string;
  file_path: string | null;
  created_at: string;
  addressed: number;
  addressed_at: string | null;
  addressed_notes: string | null;
}

interface Workflow {
  id: number;
  run_id: number;
  workflow_name: string;
  status: string;
  conclusion: string | null;
  created_at: string;
  completed_at: string | null;
  failure_details: string | null;
}

interface Activity {
  id: number;
  activity_type: string;
  activity_time: string;
  summary: string;
  details: string | null;
  actor: string;
}

// Global state
let currentPR: PR | null = null;
let currentTab: 'overview' | 'comments' | 'workflows' | 'activities' = 'overview';

// Initialize app
document.addEventListener('DOMContentLoaded', () => {
  initTabs();
  loadStats();
  loadMonitors();
  loadPRs();
  loadDetectedPR();

  // Refresh every 30 seconds
  setInterval(() => {
    loadStats();
    const activeTab = document.querySelector('.tab-button.active')?.getAttribute('data-tab');
    if (activeTab === 'monitors') {
      loadMonitors();
    } else if (activeTab === 'prs') {
      loadPRs();
    }
  }, 30000);
});

// Tab management
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

// Load stats
async function loadStats() {
  try {
    const [statsResponse, monitorsResponse] = await Promise.all([
      fetch(`${API_BASE}/stats`),
      fetch(`${API_BASE}/monitors`)
    ]);

    const statsData = await statsResponse.json();
    const monitorsData = await monitorsResponse.json();

    if (statsData.success) {
      document.getElementById('total-prs')!.textContent = statsData.stats.total_prs.count.toString();
      document.getElementById('open-prs')!.textContent = statsData.stats.open_prs.count.toString();
      document.getElementById('unaddressed-comments')!.textContent = statsData.stats.unaddressed_comments.count.toString();
    }

    if (monitorsData.success) {
      document.getElementById('running-monitors')!.textContent = monitorsData.monitors.length.toString();
    }
  } catch (error) {
    console.error('Failed to load stats:', error);
  }
}

// Load detected PR for current branch
async function loadDetectedPR() {
  try {
    const response = await fetch(`${API_BASE}/detect-pr`);
    const data = await response.json();

    if (data.success && data.pr) {
      // Check if this PR is already being monitored
      const monitorsResponse = await fetch(`${API_BASE}/monitors`);
      const monitorsData = await monitorsResponse.json();

      const isMonitored = monitorsData.success &&
        monitorsData.monitors.some((m: any) => m.pr_number === data.pr.number);

      showDetectedPRBanner(data.pr, data.branch, isMonitored);
    }
  } catch (error) {
    console.error('Failed to detect PR:', error);
  }
}

// Show detected PR banner
function showDetectedPRBanner(pr: any, branch: string, isMonitored: boolean = false) {
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

// Start monitoring a PR
async function startMonitoring(prNumber: number) {
  if (!confirm(`Start monitoring PR #${prNumber}?`)) return;

  try {
    const response = await fetch(`${API_BASE}/monitors/start`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pr_number: prNumber, repo: '' })
    });

    const data = await response.json();

    if (data.success) {
      alert(`Monitor started! PID: ${data.pid}`);
      // Refresh monitors and reload detected PR banner to update button state
      loadMonitors();
      loadDetectedPR();
      loadStats();
    } else {
      // Handle duplicate monitor case
      if (data.code === 'ALREADY_RUNNING') {
        alert(`A monitor is already running for PR #${prNumber}.\n\nCheck the "Running Monitors" tab to manage it.`);
        // Reload banner to show "Already Monitoring" state
        loadDetectedPR();
      } else {
        alert(`Failed to start monitor: ${data.error}`);
      }
    }
  } catch (error) {
    alert(`Error starting monitor: ${error}`);
  }
}

// Load monitors
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
        return;
      }

      container.innerHTML = data.monitors.map((monitor: Monitor) => `
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
    } else {
      container.innerHTML = '<div class="empty-state">Failed to load monitors</div>';
    }
  } catch (error) {
    console.error('Failed to load monitors:', error);
    container.innerHTML = '<div class="empty-state">Error loading monitors</div>';
  }
}

// Stop monitor
async function stopMonitor(pid: number) {
  if (!confirm(`Are you sure you want to stop the monitor with PID ${pid}?`)) {
    return;
  }

  try {
    const response = await fetch(`${API_BASE}/monitors/stop/${pid}`, {
      method: 'POST'
    });
    const data = await response.json();

    if (data.success) {
      alert('Monitor stopped successfully');
      loadMonitors();
      loadStats();
    } else {
      alert(`Failed to stop monitor: ${data.error}`);
    }
  } catch (error) {
    alert(`Error stopping monitor: ${error}`);
  }
}

// Load PRs
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

      container.innerHTML = data.prs.map((pr: PR) => `
        <div class="pr-card" onclick="showPRDetail(${pr.pr_number}, '${pr.repo}')">
          <div class="pr-header">
            <div class="pr-title">
              PR #${pr.pr_number} - ${pr.title}
            </div>
            <span class="badge ${pr.state === 'open' ? 'badge-success' : 'badge-danger'}">
              ${pr.state.toUpperCase()}
            </span>
          </div>
          <div class="pr-info">
            <div class="info-item">
              <span class="info-label">Repository</span>
              <span class="info-value">${pr.repo}</span>
            </div>
            <div class="info-item">
              <span class="info-label">Author</span>
              <span class="info-value">${pr.author}</span>
            </div>
            <div class="info-item">
              <span class="info-label">Comments</span>
              <span class="info-value">
                ${pr.comment_count}
                ${pr.unaddressed_comment_count > 0 ? `<span class="badge badge-warning">${pr.unaddressed_comment_count} unaddressed</span>` : ''}
              </span>
            </div>
            <div class="info-item">
              <span class="info-label">Workflows</span>
              <span class="info-value">
                ${pr.workflow_count}
                ${pr.failed_workflow_count > 0 ? `<span class="badge badge-danger">${pr.failed_workflow_count} failed</span>` : ''}
              </span>
            </div>
            <div class="info-item">
              <span class="info-label">Last Updated</span>
              <span class="info-value">${formatDate(pr.updated_at)}</span>
            </div>
          </div>
        </div>
      `).join('');
    } else {
      container.innerHTML = '<div class="empty-state">Failed to load PRs</div>';
    }
  } catch (error) {
    console.error('Failed to load PRs:', error);
    container.innerHTML = '<div class="empty-state">Error loading PRs</div>';
  }
}

// Show PR detail modal
async function showPRDetail(prNumber: number, repo: string) {
  const modal = document.getElementById('pr-modal');
  if (!modal) return;

  modal.classList.add('active');

  try {
    const response = await fetch(`${API_BASE}/prs/${prNumber}?repo=${encodeURIComponent(repo)}`);
    const data = await response.json();

    if (data.success) {
      currentPR = data.pr;
      renderPRDetail();
    } else {
      alert('Failed to load PR details');
      closeModal();
    }
  } catch (error) {
    console.error('Failed to load PR details:', error);
    alert('Error loading PR details');
    closeModal();
  }
}

// Render PR detail
function renderPRDetail() {
  if (!currentPR) return;

  const modalTitle = document.getElementById('modal-title');
  const modalBody = document.getElementById('modal-body');

  if (modalTitle) {
    modalTitle.textContent = `PR #${currentPR.pr_number} - ${currentPR.title}`;
  }

  if (modalBody) {
    modalBody.innerHTML = `
      <div class="modal-tabs">
        <button class="modal-tab ${currentTab === 'overview' ? 'active' : ''}" onclick="switchModalTab('overview')">Overview</button>
        <button class="modal-tab ${currentTab === 'comments' ? 'active' : ''}" onclick="switchModalTab('comments')">Comments</button>
        <button class="modal-tab ${currentTab === 'workflows' ? 'active' : ''}" onclick="switchModalTab('workflows')">Workflows</button>
        <button class="modal-tab ${currentTab === 'activities' ? 'active' : ''}" onclick="switchModalTab('activities')">Activities</button>
      </div>
      <div id="modal-tab-content"></div>
    `;

    switchModalTab(currentTab);
  }
}

// Switch modal tab
async function switchModalTab(tab: 'overview' | 'comments' | 'workflows' | 'activities') {
  currentTab = tab;

  // Update tab buttons
  document.querySelectorAll('.modal-tab').forEach(btn => {
    btn.classList.remove('active');
  });
  document.querySelectorAll('.modal-tab').forEach(btn => {
    if (btn.textContent?.toLowerCase().includes(tab)) {
      btn.classList.add('active');
    }
  });

  const content = document.getElementById('modal-tab-content');
  if (!content || !currentPR) return;

  content.innerHTML = '<div class="loading">Loading...</div>';

  if (tab === 'overview') {
    renderOverview(content);
  } else if (tab === 'comments') {
    await renderComments(content);
  } else if (tab === 'workflows') {
    await renderWorkflows(content);
  } else if (tab === 'activities') {
    await renderActivities(content);
  }
}

// Render overview
function renderOverview(container: HTMLElement) {
  if (!currentPR) return;

  container.innerHTML = `
    <div class="detail-section">
      <h3>PR Information</h3>
      <div class="pr-info">
        <div class="info-item">
          <span class="info-label">Repository</span>
          <span class="info-value">${currentPR.repo}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Author</span>
          <span class="info-value">${currentPR.author}</span>
        </div>
        <div class="info-item">
          <span class="info-label">State</span>
          <span class="info-value">
            <span class="badge ${currentPR.state === 'open' ? 'badge-success' : 'badge-danger'}">
              ${currentPR.state.toUpperCase()}
            </span>
          </span>
        </div>
        <div class="info-item">
          <span class="info-label">Created</span>
          <span class="info-value">${formatDate(currentPR.created_at)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Last Updated</span>
          <span class="info-value">${formatDate(currentPR.updated_at)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">URL</span>
          <span class="info-value">
            <a href="${currentPR.url}" target="_blank" style="color: #667eea;">View on GitHub →</a>
          </span>
        </div>
      </div>
    </div>
  `;
}

// Render comments
async function renderComments(container: HTMLElement) {
  if (!currentPR) return;

  try {
    const response = await fetch(`${API_BASE}/prs/${currentPR.pr_number}/comments?repo=${encodeURIComponent(currentPR.repo)}`);
    const data = await response.json();

    if (data.success) {
      if (data.comments.length === 0) {
        container.innerHTML = '<div class="empty-state">No comments yet</div>';
        return;
      }

      container.innerHTML = `
        <div class="detail-section">
          <h3>Comments (${data.comments.length})</h3>
          ${data.comments.map((comment: Comment) => `
            <div class="comment-item ${comment.addressed ? 'addressed' : 'unaddressed'}">
              <div class="item-header">
                <span class="item-author">${comment.author}</span>
                <div>
                  ${comment.addressed
                    ? '<span class="badge badge-success">✓ Addressed</span>'
                    : `<button class="btn btn-success" style="padding: 5px 10px; font-size: 0.85rem;" onclick="markCommentAddressed(${comment.comment_id})">Mark as Addressed</button>`
                  }
                  <span class="item-time">${formatDate(comment.created_at)}</span>
                </div>
              </div>
              <div class="item-body">${escapeHtml(comment.body)}</div>
              ${comment.file_path ? `<div class="item-file">📄 ${comment.file_path}</div>` : ''}
              ${comment.addressed && comment.addressed_notes ? `<div class="item-file" style="color: #27ae60;">✓ ${escapeHtml(comment.addressed_notes)}</div>` : ''}
            </div>
          `).join('')}
        </div>
      `;
    } else {
      container.innerHTML = '<div class="empty-state">Failed to load comments</div>';
    }
  } catch (error) {
    console.error('Failed to load comments:', error);
    container.innerHTML = '<div class="empty-state">Error loading comments</div>';
  }
}

// Render workflows
async function renderWorkflows(container: HTMLElement) {
  if (!currentPR) return;

  try {
    const response = await fetch(`${API_BASE}/prs/${currentPR.pr_number}/workflows?repo=${encodeURIComponent(currentPR.repo)}`);
    const data = await response.json();

    if (data.success) {
      if (data.workflows.length === 0) {
        container.innerHTML = '<div class="empty-state">No workflows yet</div>';
        return;
      }

      container.innerHTML = `
        <div class="detail-section">
          <h3>Workflow Runs (${data.workflows.length})</h3>
          ${data.workflows.map((workflow: Workflow) => `
            <div class="workflow-item ${workflow.conclusion || ''}">
              <div class="item-header">
                <span class="item-author">${workflow.workflow_name}</span>
                <div>
                  <span class="badge ${
                    workflow.conclusion === 'success' ? 'badge-success' :
                    workflow.conclusion === 'failure' ? 'badge-danger' :
                    'badge-warning'
                  }">
                    ${workflow.conclusion?.toUpperCase() || workflow.status.toUpperCase()}
                  </span>
                  <span class="item-time">${formatDate(workflow.created_at)}</span>
                </div>
              </div>
              ${workflow.failure_details ? `<div class="item-body" style="color: #e74c3c;">${escapeHtml(workflow.failure_details)}</div>` : ''}
            </div>
          `).join('')}
        </div>
      `;
    } else {
      container.innerHTML = '<div class="empty-state">Failed to load workflows</div>';
    }
  } catch (error) {
    console.error('Failed to load workflows:', error);
    container.innerHTML = '<div class="empty-state">Error loading workflows</div>';
  }
}

// Render activities
async function renderActivities(container: HTMLElement) {
  if (!currentPR) return;

  try {
    const response = await fetch(`${API_BASE}/prs/${currentPR.pr_number}/activities?repo=${encodeURIComponent(currentPR.repo)}`);
    const data = await response.json();

    if (data.success) {
      if (data.activities.length === 0) {
        container.innerHTML = '<div class="empty-state">No activities yet</div>';
        return;
      }

      container.innerHTML = `
        <div class="detail-section">
          <h3>Activity Log (${data.activities.length})</h3>
          ${data.activities.map((activity: Activity) => `
            <div class="activity-item">
              <div class="item-header">
                <span class="item-author">${activity.summary}</span>
                <span class="item-time">${formatDate(activity.activity_time)}</span>
              </div>
              <div class="item-body">
                <span class="badge badge-info">${activity.activity_type}</span>
                by ${activity.actor}
              </div>
              ${activity.details ? `<div class="item-file">${escapeHtml(activity.details)}</div>` : ''}
            </div>
          `).join('')}
        </div>
      `;
    } else {
      container.innerHTML = '<div class="empty-state">Failed to load activities</div>';
    }
  } catch (error) {
    console.error('Failed to load activities:', error);
    container.innerHTML = '<div class="empty-state">Error loading activities</div>';
  }
}

// Mark comment as addressed
async function markCommentAddressed(commentId: number) {
  const notes = prompt('Add notes (optional):');
  if (notes === null) return; // User cancelled

  try {
    const response = await fetch(`${API_BASE}/comments/${commentId}/address`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ notes })
    });

    const data = await response.json();

    if (data.success) {
      alert('Comment marked as addressed');
      // Reload comments tab
      if (currentTab === 'comments') {
        const content = document.getElementById('modal-tab-content');
        if (content) {
          await renderComments(content);
        }
      }
    } else {
      alert(`Failed to mark comment as addressed: ${data.error}`);
    }
  } catch (error) {
    alert(`Error marking comment as addressed: ${error}`);
  }
}

// Close modal
function closeModal() {
  const modal = document.getElementById('pr-modal');
  if (modal) {
    modal.classList.remove('active');
  }
  currentPR = null;
  currentTab = 'overview';
}

// Utility functions
function formatDate(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const diff = now.getTime() - date.getTime();
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));

  if (days === 0) {
    const hours = Math.floor(diff / (1000 * 60 * 60));
    if (hours === 0) {
      const minutes = Math.floor(diff / (1000 * 60));
      return `${minutes} minutes ago`;
    }
    return `${hours} hours ago`;
  } else if (days === 1) {
    return 'Yesterday';
  } else if (days < 7) {
    return `${days} days ago`;
  } else {
    return date.toLocaleDateString();
  }
}

function escapeHtml(text: string): string {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Refresh functions (called from HTML)
function refreshMonitors() {
  loadMonitors();
  loadStats();
}

function refreshPRs() {
  loadPRs();
  loadStats();
}

// Export to global scope for onclick handlers
(window as any).startMonitoring = startMonitoring;
(window as any).stopMonitor = stopMonitor;
(window as any).showPRDetail = showPRDetail;
(window as any).switchModalTab = switchModalTab;
(window as any).closeModal = closeModal;
(window as any).markCommentAddressed = markCommentAddressed;
(window as any).refreshMonitors = refreshMonitors;
(window as any).refreshPRs = refreshPRs;
