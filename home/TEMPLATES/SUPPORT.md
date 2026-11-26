# 🛠️ Generic Support System Specification v2.1

## 📖 Table of Contents
1. [Purpose & Scope](#purpose--scope)
2. [Core Design Principles](#core-design-principles)
3. [User Roles & Permissions](#user-roles--permissions)
4. [Support Agent System](#support-agent-system)
5. [Bot Automation System (Logic-Based, No AI/ML)](#bot-automation-system-logic-based-no-aiml)
6. [Ticket Lifecycle](#ticket-lifecycle)
7. [Live Chat System](#live-chat-system)
8. [Knowledge Base](#knowledge-base)
9. [Notifications](#notifications)
10. [Security & Access Control](#security--access-control)
11. [Configuration Management](#configuration-management)
12. [Audit & Compliance](#audit--compliance)
13. [Implementation Guidelines](#implementation-guidelines)
14. [Appendix](#appendix)
15. [Key Implementation Notes](#key-implementation-notes)

---

## 🎯 Purpose & Scope

### Purpose
This is a feature template: the support domain specification (ticket lifecycle, support agents and roles, deterministic bot pre-screening, live chat, knowledge base, SLA) applied INTO an existing project by the `support-builder` agent. It is an optional, machine-level reference that informs the project's `SPEC.md` support contract.

### Precedence
The project's own `AI.md` (its project template) and `SPEC.md` win every conflict. This file never redefines what the host template already owns: configuration and `secrets.yml` handling, database and migration rules, API conventions, authentication and roles, i18n, UI and theming, logging and audit storage, testing, CI/CD and release. Where this file and the host template overlap, follow the host template and do not copy its text here, so there is one place to maintain each rule.

### What This Specification Defines
- Ticket states, transitions and data structures
- Support roles, agent mode and availability
- Logic-based bot pre-screening
- Live chat and knowledge base behavior
- SLA and escalation rules
- Support-specific notices and data access rules

### What This Specification Does NOT Define
- Programming language, framework, database schemas or API endpoint URLs
- File system paths, visual design or branding
- Specific third-party service integrations
- Internal implementation details

---

## 🏗️ Core Design Principles

### 1. User Agency Over Automation
**Principle**: While automation enhances efficiency, users maintain ultimate control over all decisions.
- Bot suggestions can always be overridden
- No automated action is final without user confirmation
- Users can modify any auto-populated data
- Clear indication of what is automated vs. user-entered

### 2. Privacy by Design
**Principle**: User data and support interactions remain private and secure.
- Tickets visible only to creator and support agents
- Support agents' admin privileges are never exposed to users
- All data access is logged and auditable
- Minimal data collection policy

### 3. Mobile-First, Accessibility-Always
**Principle**: The system must be fully functional on all devices and for all users.
- Responsive design that works on screens from 320px to 4K
- Full keyboard navigation support
- Screen reader compatibility (WCAG 2.1 AA compliant)
- Touch-optimized interfaces for mobile devices
- Reduced motion options for users with vestibular disorders

### 4. Configuration Through UI
**Principle**: System configuration happens through web interfaces; no code editing is required.
- Admin configuration panel for system settings
- Agent configuration panel for personal settings
- The admin UI writes the owning config file; credentials are stored in `secrets.yml` (mode `0600`, never committed)
- All user-facing strings are translated; keys follow the `errors.*` / `notifications.*` pattern
- All settings have sensible defaults
- Configuration changes take effect immediately (no restart required)

### 5. Fail Gracefully
**Principle**: When components fail, the system degrades gracefully.
- If bot fails → direct ticket creation remains available
- If chat fails → ticket system remains functional
- If email fails → in-app notifications continue
- Clear error messages for users and agents
- Automatic recovery when services restore

---

## 👤 User Roles & Permissions

### Role Hierarchy

#### 1. Guest User (Unauthenticated)
**Capabilities**:
- View public knowledge base articles
- Submit support tickets (with email verification)
- Access bot for initial troubleshooting
- View status of their tickets via email link

**Restrictions**:
- Cannot view other tickets
- Cannot access live chat
- Anonymous ticket and contact submission follows the shape template's report-form antispam: signed single-use form token, honeypot, CAPTCHA on every anonymous submit with a no-JS fallback, and per-field `max_length`
- Rate-limited ticket creation (configurable)

#### 2. Registered User (Authenticated)
**Capabilities**:
- All Guest User capabilities
- Create tickets without email verification
- Access live chat when agents available
- View all their historical tickets
- Update their profile and notification preferences
- Rate and provide feedback on resolved tickets

**Restrictions**:
- Can only view their own tickets
- Cannot see support agent notes
- Cannot access support dashboard
- Subject to configured rate limits

#### 3. Support Agent
**Capabilities**:
- Toggle between user mode and support mode
- View and respond to all tickets (when in support mode)
- Access internal knowledge base and notes
- Use canned responses and templates
- Set availability status for live chat
- Add internal notes to tickets
- Assign/reassign tickets
- View support metrics and queue status

**Restrictions**:
- Cannot create tickets while in support mode
- Cannot modify system configuration
- Cannot delete tickets (only archive)
- Cannot view certain admin-only logs

#### 4. System Administrator
**Capabilities**:
- All Support Agent capabilities
- Configure system settings via web UI
- Manage support agent accounts
- Customize email templates and notifications
- Configure bot settings (enable/disable, custom patterns)
- Access system logs and audit trails
- Manage knowledge base structure
- Set rate limits and security policies

**Restrictions**:
- When acting as support, appears as support agent (not admin)
- Cannot bypass audit logging
- Cannot access database directly through support interface

### Role Assignment

#### Method 1: Internal Assignment
```
User Account → Role Assignment (via admin UI) → Permissions Granted
```
- Admin manually assigns roles through web interface
- Immediate effect upon assignment
- Roles stored in application database

#### Method 2: External Authentication Mapping
```
External Auth Provider → Attribute/Claim → Role Mapping → Permissions
```
- LDAP group membership (e.g., "cn=support-staff,ou=groups,dc=company,dc=com")
- OAuth claims (e.g., "roles": ["support"])
- SAML attributes (e.g., "Department": "Customer Support")
- Automatic role sync on login
- Configurable mapping rules via UI

### Support Group Membership
- Both regular users and system administrators can be in the support group
- Support group members must switch to "Support Mode" to act as agents
- Administrators never appear as "Admin" to users - always as support agents with their configured display name

---

## 👥 Support Agent System

### Support Mode Toggle

#### Entering Support Mode
**Trigger Methods**:
1. Manual toggle switch in navigation bar
2. Accessing support dashboard URL directly
3. Clicking "Enter Support Mode" from user dashboard

**What Happens**:
1. System checks if user has support agent role
2. UI transitions to support interface
3. Banner appears indicating support mode is active
4. User's available actions change to agent actions
5. Session marked as "support_mode: true"

#### Support Mode Banner
**Location**: Top of every page (static, not sticky - scrolls with content)

**Desktop Display**:
```
┌─────────────────────────────────────────────────────────────────┐
│ 🎧 SUPPORT AGENT MODE ACTIVE - Viewing as: [Agent Display Name]  │
│ You cannot create tickets while in support mode                  │
│ Active tickets in queue: 12 | Your assigned: 3                  │
│                                         [Exit Support Mode]      │
└─────────────────────────────────────────────────────────────────┘
```

**Mobile Display**:
```
┌────────────────────────────┐
│ 🎧 SUPPORT MODE            │
│ As: [Name] | Queue: 12     │
│         [Exit Mode]        │
└────────────────────────────┘
```

**Banner Properties**:
- Background color: Configurable (default: blue/purple)
- Text color: High contrast based on background
- Font size: System default with 1.1x scaling
- Z-index: Below modals but above content
- Animation: Slide down on enter, slide up on exit
- Persistence: Remains across page navigations while in mode
- Mobile-friendly: Does not stick to viewport on scroll

#### In Support Mode

**Enabled Features**:
- Support dashboard access
- All tickets visible in queue
- Ticket filtering and search across all users
- Ability to reply to any ticket
- Internal notes on tickets
- Ticket assignment capabilities
- Canned response library (system and personal)
- Support metrics dashboard
- Live chat agent console
- Bulk ticket operations

**Disabled Features**:
- "Create New Ticket" button (disabled with tooltip explanation)
- Bot interaction flow
- Personal ticket view (only see all tickets)
- User preferences editing
- Normal user dashboard

**UI Differences**:
- Navigation bar shows support-specific menu
- Different color scheme (configurable)
- Browser tab title prefixed with "[Support]"
- Breadcrumbs show "Support > [Current Page]"
- Footer shows "Support Mode Active"

#### Exiting Support Mode

**Trigger Methods**:
1. Click "Exit Support Mode" in banner
2. Toggle switch in navigation
3. Logout (always returns to user mode on next login)

**What Happens**:
1. Confirmation if agent has unsaved work
2. UI transitions back to user interface
3. Banner disappears
4. User's available actions return to normal
5. Session marked as "support_mode: false"
6. Any draft responses are saved for later

### Agent Display Names

#### Configuration
**Where**: Web UI → Support Settings → My Agent Profile

**Fields**:
- **Display Name** (required): What users see
  - Examples: "Sarah", "Tech Support - John", "Alex from Billing"
  - Character limit: 50 characters
  - Allowed characters: Letters, numbers, spaces, hyphens
- **Fallback**: If not set, shows "Support Agent"
- **Avatar** (optional): Image or initials
- **Specialty Tags** (optional): "Billing", "Technical", "Account"

#### Display Rules
- In tickets: "Sarah replied to your ticket"
- In chat: "You're chatting with Sarah"
- In email: "From: Sarah (Support Team)"
- Never shows: "Admin John" or role indicators
- System administrators appear with their support display name, not as "Admin"

### Agent Availability

#### Status Options
1. **Available** (Green)
   - Can receive chats
   - Visible in chat queue
   - New tickets can be auto-assigned

2. **Busy** (Yellow)
   - No new chats
   - Finishing current conversations
   - Still working tickets

3. **Away** (Gray)
   - No chats or auto-assignments
   - Manual ticket work only
   - Shows "Back at [time]" if set

4. **Offline** (Red)
   - Not logged in or support mode off
   - Not counted in available agents

#### Automatic Status Management
- Set to "Away" after 15 minutes of inactivity (configurable)
- Set to "Offline" on logout or session timeout
- Optional: Set to "Busy" when reaching chat limit
- Returns to previous status on activity

---

## 🤖 Bot Automation System (Logic-Based, No AI/ML)

### Core Principle: Deterministic Logic Only

**Production Runtime**:
- Pure pattern matching (regex, string comparison)
- Static, pre-compiled patterns
- Deterministic responses
- No machine learning inference
- No API calls to AI services
- 100% predictable behavior
- Works completely offline

### Architecture

#### Components

**1. Knowledge Base Scanner**
- Indexes all documentation on startup
- Refreshes index when documents change
- Creates searchable patterns from content
- Maintains relevance scoring

**Security Note**: The bot operates in a completely isolated environment. Its pattern database, error codes, and solution mappings are never exposed through any endpoint, API, or interface. This prevents reverse engineering of support patterns and protects against exploitation.

**2. Error Database** (Internal system component - completely isolated)

**Access Restrictions**:
- Not exposed via any API endpoint
- Not accessible through web UI
- Not visible to support agents
- Only accessible by the bot process itself
- No human-readable interface needed
- Stored in optimized format for your implementation

**Storage Format Examples** (Implementation Choice):
```
Option 1: Database table (encrypted)
Option 2: Compiled into application binary
Option 3: In-memory data structure
Option 4: Secure key-value store
Option 5: Whatever works for your architecture
```

The actual format depends on your tech stack - could be:
- Database rows
- Compiled constants
- Binary data
- Encrypted configuration
- Memory-mapped files
- Redis/cache layer

**Security Requirements**:
- Runs in isolated process/container
- No network exposure
- Read-only access from bot process
- Updated only through secure deployment
- No logging of actual patterns (security through obscurity)

**3. Pattern Matching Engine**
- Regex-based pattern matching
- Exact string matching for error codes
- Keyword density analysis
- Confidence scoring (0-100)
- Only responds at 100% confidence
- **NO AI/ML** - Uses pre-generated patterns only
- Patterns loaded from implementation-specific storage
- Could be from database, memory, compiled code, etc.

**4. Conversation Manager**
- Maintains conversation context
- Tracks attempted solutions
- Generates ticket payload
- Manages retry counter
- Maximum 3 attempts before creating ticket

### Built-in Pattern Recognition (No Configuration Needed)

**Hybrid Approach: Universal + Project-Specific Patterns**

The bot uses two layers of patterns:
1. **Universal Patterns** (Built-in) - Work for any project
2. **Project Patterns** (generated at build time from the codebase) - Specific to your project

At build time the pattern generator will:
- Keep all universal patterns as the foundation
- Scan your project for specific errors, endpoints, features
- Generate additional patterns unique to your system
- Compile both into the optimized bot database
- No manual configuration required

**Pre-defined Universal Patterns**:
The bot comes with standard patterns that work for any system:

**Authentication Issues**:
- Patterns: "can't log in", "cannot login", "authentication failed", "invalid password", "account locked"
- Solutions: Clear cache, reset password, check account status
- Auto-detects: Email validation issues, 2FA problems

**Performance Issues**:
- Patterns: "slow", "loading forever", "takes too long", "not responding", "frozen"
- Solutions: Check connection, clear cache, try different browser, check system status
- Auto-detects: Timeout errors, latency issues

**Access/Permission Issues**:
- Patterns: "access denied", "not authorized", "permission denied", "can't access", "forbidden"
- Solutions: Verify account permissions, check subscription status, contact admin for access
- Auto-detects: 403 errors, role-based access issues

**Error Messages**:
- Patterns: Any message containing "error", "exception", "failed to", specific error codes
- Solutions: Searches knowledge base for error code, provides standard troubleshooting
- Auto-detects: Stack traces, error codes, system messages

**Payment/Billing**:
- Patterns: "payment failed", "card declined", "billing", "subscription", "refund"
- Solutions: Update payment method, check card details, verify billing address
- Auto-detects: Transaction IDs, payment processor responses

**Data/Sync Issues**:
- Patterns: "not syncing", "data missing", "lost my", "disappeared", "not saving"
- Solutions: Check connection, refresh, verify auto-save settings, check recycle bin
- Auto-detects: Sync conflicts, version mismatches

**Installation/Setup**:
- Patterns: "how to install", "setup", "getting started", "first time", "new user"
- Solutions: Links to quick start guide, setup checklist, video tutorials
- Auto-detects: Configuration issues, missing dependencies

**Bug Reports**:
- Patterns: "bug", "broken", "doesn't work", "not working properly"
- Solutions: Gather browser/OS info, steps to reproduce, known issues check
- Auto-detects: Browser console errors, device-specific issues

**How-to Questions**:
- Patterns: "how do I", "how to", "where is", "can't find"
- Solutions: Searches documentation, provides navigation help
- Auto-detects: Feature location questions, UI navigation

**Account Management**:
- Patterns: "delete account", "change email", "update profile", "cancel subscription"
- Solutions: Links to account settings, provides step-by-step guide
- Auto-detects: Profile update requests, account closure

### Smart Pattern Matching Logic

**Built-in Intelligence** (No configuration required):
1. **Error Code Detection**: Automatically extracts any pattern like "ERR_*", "ERROR *", "[0-9]{3,5}" 
2. **URL Detection**: Identifies problematic URLs or pages mentioned
3. **Timestamp Detection**: Recognizes when issues occurred
4. **Frequency Detection**: Identifies if user mentions "always", "sometimes", "randomly"
5. **Urgency Detection**: Recognizes "urgent", "ASAP", "production down", "critical"
6. **Sentiment Analysis**: Simple negative keyword detection for escalation

**Category Auto-Detection**:
- Technical (errors, bugs, performance)
- Account (login, profile, permissions)
- Billing (payment, subscription, refunds)
- General (how-to, features, documentation)

### Bot Interaction Flow

#### Phase 1: Initial Contact (Mandatory Before Ticket Creation)
Anonymous ticket submission follows the report-form antispam rules (see Guest User restrictions).
```
User: Clicks "Get Support"
     ↓
Bot: "Hello! I'm the support bot. I'll try to help you resolve your issue quickly. 
      Please describe what you're experiencing."
     ↓
User: Describes issue
     ↓
Bot: Analyzes input
```

#### Phase 2: Solution Attempts (Maximum 3)

**Attempt Structure**:
```
Bot: "I found something that might help with [issue summary]:"
     
     📚 Relevant Article: [Title with link]
     
     Solution Steps:
     1. [Step one with specific action]
     2. [Step two with expected result]
     3. [Step three if needed]
     
     ⚡ Quick Actions:
     [Button: Clear Cache] [Button: Reset Password] [Button: Check Status]
     
     Did this resolve your issue?
     [Yes, resolved] [No, still having issues]
```

**If User Says "No"**:
- Bot attempts up to 2 more different solutions
- Each attempt must be substantially different
- Bot tracks what has been tried

**If User Says "Yes"**:
- Bot confirms resolution
- Asks for optional feedback
- Logs successful resolution pattern
- Ends conversation

#### Phase 3: Ticket Creation (After 3 Failed Attempts)

**Bot Response**:
```
Bot: "I understand this issue needs human attention. I'll help you create a 
      support ticket with the information we've gathered."
      
      Here's what I've prepared:
      • Issue Summary: [Generated from conversation]
      • Solutions Attempted: [List of tried solutions]
      • Category: [Auto-detected category]
      • Priority: [Based on urgency keywords]
      
      [Open Ticket Form]
```

**Generated Ticket Payload**:
- Title (auto-generated from issue keywords)
- Description (user's original description + context)
- Category (auto-detected)
- Priority (based on keywords: production, urgent, etc.)
- Bot conversation history
- Solutions already attempted
- Metadata (timestamp, user agent, referrer)

**User Control**:
- User can modify ALL fields before submission
- Change category if bot was wrong
- Adjust priority level
- Add additional details
- User must click "Submit Ticket" - bot never saves

### Optional Admin Overrides

While the system works out-of-the-box with built-in patterns (and project patterns generated at build time), admins can optionally:
- **Disable** specific built-in patterns (not modify them)
- **Add** organization-specific patterns for unique features
- **Set** category priorities
- **Configure** escalation keywords for their industry
- **Toggle** bot on/off entirely

**Admin UI Simplified**:
```
Bot Configuration
━━━━━━━━━━━━━━━━
Status: [● Enabled ○ Disabled]

Built-in Patterns: ✓ Active (Recommended)

Custom Patterns (Optional):
[+ Add Organization-Specific Pattern]

Escalation Words (Optional):
[Default list + Add custom words]

[Save Settings]
```

### Bot Limitations

**Cannot Do**:
- Make changes to user accounts
- Access private user data
- Close or resolve tickets
- Save tickets (user must confirm)
- Override user decisions
- Respond below 100% confidence
- Access external APIs without configuration

**Must Do**:
- Clearly identify as bot
- Show confidence level
- Log all interactions
- Respect user choices
- Provide escape to human support
- Maintain conversation context
- Generate accurate ticket summaries

### Bot Analytics

**Tracked Metrics**:
- Resolution rate (solved without ticket)
- Average attempts before resolution
- Most common patterns
- Failed pattern matches
- User satisfaction scores
- Time to resolution
- Category distribution
- User override frequency (when they change bot's categorization)

---

## 📋 Ticket Lifecycle

### States & Transitions

#### State Definitions

**1. DRAFT** (User-side only)
- Ticket being composed
- Auto-saved every 30 seconds
- Not visible to support
- Can be abandoned

**2. OPEN**
- Newly submitted ticket
- Awaiting initial response
- Visible in support queue
- SLA timer starts

**3. ASSIGNED**
- Claimed by specific agent
- Agent is responsible
- Others can still view/help
- Shows agent name

**4. IN_PROGRESS**
- Agent actively working
- May be gathering info
- User sees "Agent is working on this"
- No response required yet

**5. AWAITING_USER**
- Agent has responded
- Needs user input
- SLA timer paused
- Reminder sent after X days

**6. AWAITING_AGENT**
- User has responded
- Back in agent queue
- SLA timer resumes
- Priority may increase

**7. RESOLVED**
- Solution provided
- Awaiting user confirmation
- Can be reopened by user
- Triggers satisfaction survey

**8. CLOSED**
- Confirmed resolved or auto-closed
- Read-only state
- Archived after X days
- Can be reopened (configurable)

**9. REOPENED**
- User reactivated closed ticket
- Returns to OPEN state
- Maintains history
- Higher priority flag

#### State Transition Rules

```
DRAFT → OPEN: User submits
OPEN → ASSIGNED: Agent claims
ASSIGNED → IN_PROGRESS: Agent starts work
IN_PROGRESS → AWAITING_USER: Agent responds
AWAITING_USER → AWAITING_AGENT: User responds
AWAITING_AGENT → AWAITING_USER: Agent responds
* → RESOLVED: Agent marks resolved
RESOLVED → CLOSED: User confirms or timeout
CLOSED → REOPENED: User requests
REOPENED → OPEN: System automatic
* → CLOSED: Admin force close
```

### Ticket Data Structure

#### Core Fields

**Required**:
- `ticket_id`: Unique identifier (e.g., "TKT-2024-001234")
- `title`: Brief description (max 200 chars)
- `description`: Full details (max 10,000 chars)
- `user_id`: Creator identifier
- `user_email`: Contact email
- `category`: From predefined list or bot-detected
- `status`: Current state
- `created_at`: Timestamp
- `updated_at`: Last modification

**Optional/Auto-populated**:
- `priority`: LOW | NORMAL | HIGH | URGENT
- `assigned_to`: Agent ID
- `bot_metadata`: Bot conversation data
- `tags`: Flexible labeling
- `custom_fields`: Project-specific data
- `attachments`: File references
- `related_tickets`: Linked issues
- `resolution`: How it was solved
- `time_spent`: Agent work time

#### Thread Structure

Each ticket maintains a threaded conversation with:
- User messages
- Agent messages
- System events
- Internal notes (agent-only)
- Timestamps
- Edit history
- Attachments

### Ticket Operations

#### User Operations

**Can Always Do**:
- View own tickets
- Add replies
- Upload attachments (size/type limits)
- Request reopening
- Rate resolved tickets
- Modify ticket details before submission

**Cannot Do**:
- Delete tickets
- View other users' tickets
- See internal notes
- Change assignment
- Modify priority (unless configured)

#### Agent Operations

**Can Do**:
- View all tickets
- Assign/reassign
- Change priority
- Add internal notes
- Merge related tickets
- Add tags
- Set reminders
- Use canned responses
- Link tickets

**Need Permission For**:
- Delete tickets
- Modify user data
- Bypass SLA
- Access deleted tickets

### SLA & Escalation (Optional Configuration)

#### SLA Levels

Configure via Web UI per category/priority:

```
URGENT: First response: 1 hour, Resolution: 4 hours
HIGH: First response: 4 hours, Resolution: 1 day
NORMAL: First response: 1 day, Resolution: 3 days
LOW: First response: 3 days, Resolution: 7 days
```

#### Escalation Rules

**Automatic Escalation Triggers**:
- SLA breach imminent (80% of time elapsed)
- SLA breached
- User mentions keywords ("urgent", "production down")
- Multiple reopens
- VIP user flag

**Escalation Actions**:
- Increase priority
- Notify senior agents
- Add to priority queue
- Send manager alert
- Auto-assign to available senior agent

---

## 💬 Live Chat System

### Availability Logic

#### System Availability Check
```
Is Chat Available = (
  At least one agent status == "Available" AND
  Total active chats < max_concurrent_chats AND
  Current time within business hours (if configured) AND
  Chat feature enabled globally
)
```

#### User Interface Changes

**When Available**:
```html
[💬 Live Chat - Agent Available]
Click to start a conversation
```

**When Unavailable**:
```html
[📧 Leave a Message]
No agents available - Create a ticket
Expected response time: ~2 hours
```

### Chat Initialization

#### User Starts Chat

**Pre-chat Form** (Optional):
```
┌─────────────────────────────┐
│ Start Live Chat             │
├─────────────────────────────┤
│ Name: [_______________]     │
│ Email: [______________]     │
│ Topic: [Dropdown      ▼]    │
│                             │
│ [Start Chat] [Cancel]       │
└─────────────────────────────┘
```

**Chat Assignment**:
1. System finds available agents
2. Applies routing rules:
   - Least busy (fewest active chats)
   - Round-robin
   - Specialty matching
   - Previous agent (if configured)
3. Assigns to selected agent
4. Notifies agent immediately

### Chat Interface

#### User View
```
┌────────────────────────────────────┐
│ Support Chat - Sarah               │
├────────────────────────────────────┤
│                                    │
│ Sarah: Hi! How can I help today?  │
│                           2:34 PM  │
│                                    │
│ You: I can't access my account    │
│                           2:35 PM  │
│                                    │
│ Sarah is typing...                 │
│                                    │
├────────────────────────────────────┤
│ [Type message... (Shift+Enter to   │
│  send, Enter for new line)]        │
│ [📎] [Send]                        │
└────────────────────────────────────┘
```

#### Agent View
```
┌────────────────────────────────────┐
│ Chat with: John Doe (#USR-0923)    │
│ Email: john@example.com            │
│ Previous tickets: 3 [View]         │
├────────────────────────────────────┤
│ [Same chat content]                │
├────────────────────────────────────┤
│ Quick Actions:                     │
│ [Create Ticket] [Send Article]     │
│ [Transfer Chat] [End Chat]         │
├────────────────────────────────────┤
│ Canned Responses: [Select    ▼]    │
│ [Type message...]                  │
│ [📎] [Send]                        │
└────────────────────────────────────┘
```

### Chat Features

#### Message Features
- Real-time delivery
- Read receipts (optional)
- Typing indicators
- File sharing (size limits apply)
- Emoji support
- Link detection and preview
- Code formatting with ```
- Message editing (within 5 minutes)
- Shift+Enter to send, Enter for new line (deliberate for web-based chat — multi-line messages first; the input UI MUST document this binding visibly, e.g. the input placeholder text shown in the customer-view mockup)

#### Agent Tools
- **Canned Responses**: 
  - Quick access to system and personal templates
  - Search/filter by category or keyword
  - Auto-suggest based on chat content
  - Track usage of each response
  - One-click insertion with variable replacement
- **Article Insertion**: Share KB articles inline
- **Screen Sharing**: Optional integration point
- **Transfer**: Hand off to another agent
- **Convert to Ticket**: Create ticket from chat
- **User Info Panel**: History, tickets, notes

### Chat Conclusion

#### Ending a Chat

**Agent Ends Chat**:
1. Agent clicks "End Chat"
2. Confirmation prompt
3. Optional wrap-up notes
4. Chat converts to ticket (optional)
5. Satisfaction survey triggered

**User Ends Chat**:
1. User closes window or clicks "End"
2. Confirmation prompt
3. Option to download transcript
4. Option to create ticket
5. Chat saved to history

**System Timeout**:
- Warning after 10 minutes inactivity
- Auto-end after 15 minutes
- Saves transcript
- Notifies both parties

#### Post-Chat

**Transcript Handling**:
- Saved to user's history
- Optionally converted to ticket
- Available for download
- Searchable in support dashboard

---

## 📚 Knowledge Base

### Structure

#### Public Knowledge Base
**Storage**: Public documentation area
**Access**: Everyone
**Content Types**:
- Getting started guides
- FAQs
- Troubleshooting articles
- Feature documentation
- Video tutorials (links)

#### Internal Knowledge Base
**Storage**: Internal documentation area
**Access**: Support agents only
**Content Types**:
- Internal procedures
- Escalation guides
- Known issues
- Workarounds
- Customer notes

### Article Format

#### Metadata Header (YAML)
```yaml
---
title: "How to Reset Your Password"
category: "Account Management"
tags: ["password", "login", "security"]
author: "Sarah Johnson"
created: 2024-01-15
updated: 2024-10-30
visibility: "public|internal"
priority: 1
related: ["article-id-1", "article-id-2"]
---
```

#### Content (Markdown)
Articles written in Markdown format with:
- Clear headings
- Step-by-step instructions
- Screenshots (where applicable)
- Related articles
- Troubleshooting sections

### Search & Discovery

#### Search Algorithm
1. **Title Match** (highest weight)
2. **Tag Match** (high weight)
3. **Content Match** (medium weight)
4. **Related Articles** (low weight)

#### Bot Integration
- Bot searches KB before attempting solutions
- Articles ranked by relevance and success rate
- Bot tracks which articles resolve issues
- Failed articles get lower ranking

#### User Features
- Search as you type
- Category filtering
- Most helpful articles
- Recently updated
- Related articles sidebar

### Management

#### Article Lifecycle
1. **Draft**: Being written
2. **Review**: Awaiting approval
3. **Published**: Live and searchable
4. **Archived**: Outdated but preserved

#### Analytics Tracked
- View count
- Helpful/not helpful votes
- Bot usage frequency
- Resolution success rate
- Search queries leading to article
- Time on page
- Bounce rate

---

## 📬 Notifications

### Notification Rules

#### User Preferences
Configurable per user:
- Email for ticket updates
- Email for status changes
- In-app notifications
- Push notifications
- Quiet hours
- Batching preferences

#### Smart Batching
- Combine multiple updates within 5 minutes
- Never batch urgent/SLA notifications
- Respect user's time zone
- Don't send between 10 PM - 8 AM (configurable)

---

## 🔐 Security & Access Control

### Data Access Controls

#### Bot System Isolation
**Complete Separation**:
- Bot pattern database has no API endpoints
- No URL routes to bot internals
- No database queries can access bot patterns
- Support agents cannot view bot logic
- Even admins only configure via UI, never see compiled format

**Why This Matters**:
- Prevents pattern exploitation
- Protects business logic
- Avoids social engineering (users can't learn what triggers solutions)
- Maintains security through obscurity
- Reduces attack surface

#### Ticket Visibility Matrix
```
              View Own | View All | Modify Own | Modify All
Guest         Limited  |    No    |     No     |     No
User            Yes    |    No    |    Yes     |     No
Support (Off)   Yes    |    No    |    Yes     |     No
Support (On)    N/A    |   Yes    |     No     |    Yes
Admin           N/A    |   Yes    |     No     |    Yes
```

#### Sensitive Data Handling
- PII masked in logs
- Credit cards never stored
- Passwords never in tickets
- Attachments virus-scanned
- Data retention policies enforced

## ⚙️ Configuration Management

### Web UI Configuration

#### System Settings (Admin Only)
```
Support System Settings
━━━━━━━━━━━━━━━━━━━━━

General
├── System Name: [________________]
├── Support Email: [______________]
├── Time Zone: [UTC ▼]
└── Language: [English ▼]

Features
├── ☑ Enable Bot Pre-screening
├── ☑ Enable Live Chat
├── ☐ Enable Guest Tickets
├── ☑ Enable File Attachments
└── ☐ Enable Satisfaction Surveys

Limits
├── Max Ticket Size: [10000] characters
├── Max Attachment: [25] MB
├── Rate Limit: [10] tickets/hour
└── Chat Timeout: [15] minutes

Business Hours
├── Monday-Friday: [9:00 AM - 5:00 PM]
├── Saturday-Sunday: [Closed]
└── Holidays: [Configure...]
```

#### Email Templates (Admin Only)
- Rich text editor with variable insertion
- Preview before save
- Test send functionality
- Revert to default option
- Multi-language support

#### Bot Configuration (Admin Only)
**Minimal Configuration Required** - Works out-of-the-box with built-in patterns

**Simple Toggle Settings**:
- Enable/Disable bot entirely
- Maximum attempts before ticket (1-5, default: 3)
- Response timeout (default: 5 seconds)
- Business hours only (optional)

**Optional Customization**:
- Add organization-specific patterns
- Add custom escalation keywords
- Disable specific built-in patterns
- Set category priorities

**Analytics Dashboard** (View-only):
- Pattern match success rates
- Most common issues
- Resolution rates
- Average attempts to resolution
- User satisfaction with bot responses

#### Canned Responses Management (Admin Only)
**System-wide Canned Responses**:
- Create organizational templates for consistency
- Categorize by type (greeting, troubleshooting, closing, escalation)
- Set permissions (which agents can use which responses)
- Include variables for personalization: {{user_name}}, {{ticket_id}}, {{agent_name}}
- Version control with edit history
- Usage analytics (which responses are most used/effective)
- Mark as mandatory (agents must use for certain scenarios)
- Multi-language versions of same response

**Admin Controls**:
```
System Canned Responses
━━━━━━━━━━━━━━━━━━━━━
[+ Add New Response]

Category: [Greeting ▼]
Title: Welcome Message
Content: [Rich text editor with variables]
Tags: [greeting, initial]
Available to: [All Agents ▼]
Language: [English ▼]
Status: [Active ▼]

[Save] [Preview] [Delete]
```

**Hierarchy**:
1. System responses (admin-created, all agents)
2. Department responses (admin-created, specific teams)
3. Personal responses (agent-created, individual use)

### Agent Personal Settings

```
My Support Profile
━━━━━━━━━━━━━━━━

Display Name: [Sarah from Support]
Avatar: [Upload Image]
Specialties: [Technical, Billing]
Signature: [Best regards,\nSarah]

Preferences
├── ☑ Sound for new tickets
├── ☑ Desktop notifications
├── ☐ Auto-accept chats
└── ☑ Show keyboard shortcuts

Canned Responses
├── System Responses (View Only)
│   ├── "Welcome to support..." [View]
│   └── "Escalating to senior..." [View]
├── Personal Responses
│   ├── [+ Add Personal Response]
│   ├── "Thanks for contacting..." [Edit]
│   └── "Have you tried..." [Edit]
```

**Response Selection Priority**:
When agents select canned responses:
1. System mandatory responses (must use for specific triggers)
2. System suggested responses (recommended by admin)
3. Department/team responses (if applicable)
4. Personal responses (agent's own)

---

## 📊 Audit & Compliance

### Data Retention

#### Configurable Policies
```yaml
Tickets:
  active: "No limit"
  closed: "2 years"
  deleted: "30 days (soft delete)"
  
Chats:
  transcripts: "1 year"
  
Logs:
  audit: "7 years"
  system: "90 days"
  
Attachments:
  active_ticket: "No limit"
  closed_ticket: "1 year"
  orphaned: "30 days"
```

## 🚀 Implementation Guidelines

### Required Entities (Minimum)
- Users
- Tickets
- Messages/Replies
- Attachments
- Categories
- Agent_Assignments
- Audit_Logs
- Configuration
- Knowledge_Articles
- Chat_Sessions
- Canned_Responses

### Indexing Strategy
- ticket_id (primary)
- user_id + status (compound)
- assigned_to + status (compound)
- created_at (timestamp)
- Full-text on title, description

Schemas, migrations, performance targets, testing and deployment follow the host template.

---

## 📋 Appendix

### Status Codes

#### System Status Codes
```
200 - Success
201 - Created
400 - Bad Request
401 - Unauthorized
403 - Forbidden
404 - Not Found
429 - Rate Limited
500 - Server Error
503 - Maintenance Mode
```

## 📝 Key Implementation Notes

1. **Bot is Mandatory**: Users must interact with the bot before creating tickets
2. **Support Mode is Required**: Agents cannot create tickets while in support mode
3. **No AI in Production**: All pattern matching is deterministic logic
4. **Configuration Through the Admin UI**: the UI writes the owning config file; credentials live in `secrets.yml` (0600)
5. **Patterns are Pre-generated**: Either built-in or generated at build time
6. **Agent Names are Personalized**: Never show role hierarchy to users
7. **Everything is Audited**: All actions are logged for compliance

---

*This specification is designed to be implementation-agnostic and can be adapted to any technology stack, deployment environment, or scale requirement. All features marked as "optional" or "configurable" can be enabled or disabled based on project needs.*

*AI tools mentioned are for development assistance only. The production system runs entirely on deterministic logic with no machine learning or AI inference.*
