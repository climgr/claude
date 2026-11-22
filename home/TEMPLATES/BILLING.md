# 💳 Universal Billing System Specification v2.1

## 📖 Table of Contents
1. [Purpose & Scope](#purpose--scope)
2. [Core Design Principles](#core-design-principles)
3. [Account & Identity Management](#account--identity-management)
4. [Subscription Plans & Products](#subscription-plans--products)
5. [Billing Lifecycle](#billing-lifecycle)
6. [Payment Processing](#payment-processing)
7. [Usage Metering & Limits](#usage-metering--limits)
8. [Tax Compliance](#tax-compliance)
9. [Invoicing System](#invoicing-system)
10. [Provider Management](#provider-management)
11. [Integrated Help System](#integrated-help-system)
12. [Notification System](#notification-system)
13. [User Self-Service](#user-self-service)
14. [Administrative Controls](#administrative-controls)
15. [Security & Compliance](#security--compliance)
16. [Failure Handling & Recovery](#failure-handling--recovery)
17. [Audit & Reporting](#audit--reporting)
18. [Integration Points](#integration-points)
19. [AI Development Guidelines](#ai-development-guidelines)
20. [Implementation Guidelines](#implementation-guidelines)
21. [Appendix](#appendix)

---

## 🎯 Purpose & Scope

### Purpose
This specification defines a complete billing and subscription management system designed to be integrated into any type of project—SaaS applications, self-hosted software, enterprise platforms, marketplaces, or digital services. It provides flexible subscription management, multi-provider payment processing (with 47+ providers all disabled by default), usage-based billing, tax compliance, and comprehensive financial controls with integrated setup guidance.

### Scope
- **Language/Framework Agnostic**: Implementable in any programming language or framework
- **Database Agnostic**: Works with any database system (SQL or NoSQL)
- **Payment Provider Agnostic**: Supports 47+ payment gateways, all disabled by default
- **Deployment Agnostic**: Cloud, on-premise, hybrid, or distributed
- **Business Model Agnostic**: Subscription, one-time, usage-based, or hybrid pricing
- **Configuration Method**: Admin UI writes provider credentials to `secrets.yml` (mode `0600`, never committed)
- **Localization**: All user-facing strings are translated; keys follow the `errors.*` / `notifications.*` pattern

### What This Specification Defines
- Billing state machines and transitions
- Payment processing workflows with 47+ provider options
- Tax calculation and compliance rules
- Usage metering and enforcement
- Administrative and user interfaces with integrated help
- Security and compliance requirements
- Failure scenarios and recovery procedures
- In-UI setup guidance and tooltips

### What This Specification Does NOT Define
- Specific payment provider APIs
- Database schemas or table structures
- API endpoint URLs or naming conventions
- Currency conversion rates or methods
- Specific tax rates or jurisdictions
- Visual design or UI layouts
- Third-party service credentials
- Implementation language or framework

---

## 🏗️ Core Design Principles

### 1. Provider Independence & Zero-Default
**Principle**: System ships with NO active payment providers. All 47+ providers are disabled by default.
- All providers disabled on installation
- Web UI configuration required for activation
- System works with zero providers (invoice-only)
- No vendor lock-in
- Provider credentials never in code

### 2. Billing Continuity
**Principle**: Billing operations must continue even when providers fail.
- Invoices always generated
- Grace periods for failures
- Offline operation capability
- Automatic reconciliation
- Failover through enabled providers

### 3. Transparency & Auditability
**Principle**: Every billing action must be traceable and reversible.
- Complete audit trails
- Immutable invoice records
- Clear state transitions
- Detailed activity logs
- Provider action tracking

### 4. Global Readiness
**Principle**: Support international commerce from day one.
- Multi-currency support
- Regional tax compliance
- Localized invoice formats
- Time zone awareness
- Regional payment methods

### 5. User Control
**Principle**: Users maintain control over their billing relationship.
- Self-service capabilities
- Clear cancellation processes
- Data portability
- No dark patterns
- Transparent pricing

### 6. Graceful Degradation
**Principle**: System degrades gracefully under failure conditions.
- Provider failures don't block access
- Tax service failures use cached rates
- Payment failures trigger grace periods
- Service continues during disputes
- Invoice-only mode fallback

### 7. Self-Contained Documentation
**Principle**: All setup instructions and help are within the UI.
- Integrated tooltips on every field
- Provider setup guides in-UI
- No external documentation needed
- Interactive troubleshooting
- Contextual help everywhere

---

## 👤 Account & Identity Management

### Account Structure

#### Core Account Model
```
Account
├── Identity (from host system)
├── Billing Profile
├── Subscription(s)
├── Payment Method(s)
├── Invoice History
├── Usage Records
├── Provider Preferences
└── Audit Trail
```

### Billing Profile

#### Required Information
- **Identity Link**: Connection to host system's user/account
- **Legal Name**: For invoice generation
- **Email Address**: Verified, for billing communications
- **Billing Address**: Full address including country
- **Currency Preference**: Default currency for transactions

#### Optional Information
- **Tax Identification**: VAT ID, EIN, GST number, etc.
- **Purchase Order Requirements**: For enterprise customers
- **Billing Contact**: Separate from account owner
- **Language Preference**: For communications
- **Invoice Customization**: Logo, notes, terms
- **Preferred Payment Provider**: From enabled providers

### Account Roles & Permissions

#### Role Hierarchy

**1. Account Owner**
- Full billing access
- Can delete payment methods
- Can cancel subscriptions
- Can authorize others
- Can select payment providers

**2. Billing Administrator**
- Manage payment methods
- View/download invoices
- Modify subscription
- Cannot delete account
- Can change provider preference

**3. Billing Viewer**
- View invoices only
- View subscription status
- Cannot make changes
- Read-only access
- See payment history

**4. Finance Auditor**
- Export financial data
- View audit logs
- Generate reports
- No modification rights
- Provider transaction access

#### Permission Matrix
```
                    Owner | Admin | Viewer | Auditor
Add Payment Method    ✓   |   ✓   |   ✗    |    ✗
Remove Payment Method ✓   |   ✗   |   ✗    |    ✗
Change Subscription   ✓   |   ✓   |   ✗    |    ✗
Cancel Subscription   ✓   |   ✓   |   ✗    |    ✗
View Invoices        ✓   |   ✓   |   ✓    |    ✓
Download Invoices    ✓   |   ✓   |   ✓    |    ✓
View Audit Logs      ✓   |   ✓   |   ✗    |    ✓
Export Data          ✓   |   ✓   |   ✗    |    ✓
Select Provider      ✓   |   ✓   |   ✗    |    ✗
```

### Account Lifecycle

#### States
1. **PENDING**: Account created, awaiting billing setup
2. **TRIAL**: In trial period (if applicable)
3. **ACTIVE**: Valid subscription, payments current
4. **PAST_DUE**: Payment failed, in grace period
5. **SUSPENDED**: Grace period expired, limited access
6. **CANCELLED**: User cancelled, awaiting end of period
7. **TERMINATED**: Fully terminated, data retention only

#### State Transitions
```
PENDING → TRIAL: Trial activated
PENDING → ACTIVE: Payment method added
TRIAL → ACTIVE: Trial converted
TRIAL → CANCELLED: Trial not converted
ACTIVE → PAST_DUE: Payment failed
PAST_DUE → ACTIVE: Payment recovered
PAST_DUE → SUSPENDED: Grace period expired
SUSPENDED → ACTIVE: Payment recovered
ACTIVE → CANCELLED: User cancels
CANCELLED → TERMINATED: Billing period ends
* → TERMINATED: Admin force termination
```

---

## 📦 Subscription Plans & Products

### Plan Structure

#### Core Plan Model
```
Plan
├── Identification
│   ├── Unique ID
│   ├── Display Name
│   ├── Description
│   └── SKU/Code
├── Pricing
│   ├── Base Price
│   ├── Currency
│   ├── Billing Cycles
│   └── Discounts
├── Features
│   ├── Included Resources
│   ├── Limits & Quotas
│   └── Feature Flags
├── Terms
│   ├── Trial Period
│   ├── Grace Period
│   ├── Renewal Rules
│   └── Cancellation Policy
└── Metadata
    ├── Visibility
    ├── Availability Rules
    ├── Provider Restrictions
    └── Custom Attributes
```

### Billing Cycles

#### Supported Cycles
```
MONTHLY: Base price
QUARTERLY: 5% discount (optional)
SEMI_ANNUAL: 10% discount (optional)
ANNUAL: 10-15% discount (configurable)
BIENNIAL: 15-20% discount (configurable)
TRIENNIAL: 20-25% discount (configurable)
LIFETIME: One-time payment (special handling)
CUSTOM: Defined per implementation
```

#### Cycle Calculation
- All cycles align to calendar boundaries where possible
- Proration calculated to the day (configurable to hour)
- Leap years handled correctly
- Time zones considered for billing timing

### Plan Features & Limits

#### Resource Types
```yaml
Quantitative:
  - storage: 100GB
  - bandwidth: 1TB
  - api_calls: 10000/month
  - users: 50

Boolean:
  - advanced_analytics: true
  - priority_support: false
  - custom_domain: true

Categorical:
  - support_tier: "standard|priority|dedicated"
  - backup_frequency: "daily|hourly|realtime"
```

#### Enforcement Strategies

**Hard Limits**: Service stops at limit
```
IF usage >= limit THEN
  Block request
  Return limit exceeded error
  Prompt for upgrade
```

**Soft Limits**: Warning then overage
```
IF usage >= limit * 0.8 THEN
  Send warning notification
IF usage >= limit THEN
  Allow with overage tracking
  Bill for overage next cycle
```

**Burst Limits**: Temporary allowance
```
IF usage >= limit AND burst_available THEN
  Allow and deduct from burst pool
  Regenerate burst pool over time
```

### Plan Visibility & Availability

#### Visibility Levels
1. **PUBLIC**: Visible to all, self-service signup
2. **AUTHENTICATED**: Visible after login only
3. **INTERNAL**: Staff/beta users only
4. **INVITE_ONLY**: Requires invitation code
5. **HIDDEN**: Not visible, API activation only
6. **DEPRECATED**: Existing users only, no new signups

#### Availability Rules
- Geographic restrictions (country/region)
- Time-based availability (limited offers)
- Prerequisite requirements (must have X first)
- Capacity limits (first N customers)
- Customer type (business vs individual)
- Payment provider requirements (needs specific provider)

### Plan Transitions

#### Upgrade/Downgrade Rules
```
Immediate Upgrade:
  - Prorate current period
  - Charge difference immediately
  - Apply new limits immediately

End-of-Cycle Upgrade:
  - Queue change for next billing
  - Keep current limits until then
  - Show pending change to user

Downgrade:
  - Always at end of current period
  - Check resource usage compatibility
  - Warn about feature loss
  - Require explicit confirmation
```

---

## 💰 Billing Lifecycle

### Subscription Lifecycle

#### States
```
PENDING_ACTIVATION: Created but not yet active
TRIALING: In free trial period
ACTIVE: Paid and current
PAST_DUE: Payment failed, in grace
PAUSED: Temporarily suspended by user
CANCELLED: Cancellation scheduled
EXPIRED: Subscription ended
```

#### State Transition Diagram
```
[PENDING_ACTIVATION]
    ├── payment_added → [ACTIVE]
    └── trial_started → [TRIALING]
    
[TRIALING]
    ├── trial_converted → [ACTIVE]
    ├── trial_expired → [EXPIRED]
    └── cancelled → [CANCELLED]
    
[ACTIVE]
    ├── payment_failed → [PAST_DUE]
    ├── user_paused → [PAUSED]
    ├── cancelled → [CANCELLED]
    └── renewed → [ACTIVE]
    
[PAST_DUE]
    ├── payment_recovered → [ACTIVE]
    ├── grace_expired → [EXPIRED]
    └── cancelled → [CANCELLED]
    
[PAUSED]
    ├── resumed → [ACTIVE]
    ├── cancelled → [CANCELLED]
    └── auto_expired → [EXPIRED]
    
[CANCELLED]
    └── period_ended → [EXPIRED]
```

### Billing Events

#### Event Types
1. **SUBSCRIPTION_CREATED**: New subscription initiated
2. **TRIAL_STARTED**: Trial period began
3. **TRIAL_ENDING**: Trial ending soon (warning)
4. **PAYMENT_METHOD_ADDED**: Payment capability added
5. **BILLING_CYCLE_STARTING**: New period beginning
6. **INVOICE_GENERATED**: Invoice created
7. **PAYMENT_ATTEMPTED**: Charge attempted
8. **PAYMENT_SUCCEEDED**: Payment confirmed
9. **PAYMENT_FAILED**: Payment declined
10. **PAYMENT_RETRY_SCHEDULED**: Retry queued
11. **SUBSCRIPTION_RENEWED**: Auto-renewed
12. **SUBSCRIPTION_MODIFIED**: Plan/terms changed
13. **SUBSCRIPTION_PAUSED**: Temporarily suspended
14. **SUBSCRIPTION_RESUMED**: Reactivated
15. **SUBSCRIPTION_CANCELLED**: Cancellation requested
16. **SUBSCRIPTION_EXPIRED**: Fully terminated
17. **PROVIDER_CHANGED**: Payment provider switched
18. **PROVIDER_FAILED**: Provider unavailable

#### Event Processing
Each event triggers:
- State transition evaluation
- Notification dispatch
- Invoice generation/update
- Usage reset/carryover
- Audit log entry
- Webhook dispatch (if configured)
- Analytics tracking
- Provider failover (if needed)

### Renewal Logic

#### Auto-Renewal Process
```
Day -7: Send renewal reminder
Day -3: Verify payment method
Day -1: Pre-authorize if supported
Day 0:  
  - Generate invoice
  - Attempt payment (through enabled providers)
  - On success: Renew and reset usage
  - On failure: Try next provider or enter grace
Day +1 to +Grace: 
  - Retry daily with available providers
  - Send failure notices
  - Attempt provider recovery
Day +Grace+1:
  - Suspend service
  - Final notice
```

#### Manual Renewal Process
```
Day -14: Send renewal notice
Day -7:  Send reminder
Day -3:  Send urgent reminder
Day 0:   
  - Service continues (if configured)
  - OR enters limited mode
  - Daily reminders
Day +Grace:
  - Suspend service
  - Data preserved
```

### Grace Periods

#### Configuration
- Default: 7 days (configurable)
- Per-plan override capability
- Different periods for different failure types
- Extendable by support/admin
- Provider failure: Extended automatically

#### During Grace Period
**User Can**:
- Access service normally (configurable)
- Update payment method
- Switch payment provider
- Download data
- Contact support
- Cancel properly

**User Cannot**:
- Upgrade plan (usually)
- Add paid features
- Exceed current limits
- Transfer ownership

---

## 💳 Payment Processing

### Payment Providers Overview

**CRITICAL**: All 47+ payment providers ship DISABLED by default. Each must be explicitly configured and enabled via web UI.

### Available Payment Providers

#### Global Payment Processors (7 providers)
```yaml
Stripe:
  - Cards, Bank Transfers, Wallets
  - 135+ currencies
  - Global coverage
  - SCA/3DS support
  - Subscription management
  
PayPal/Braintree:
  - PayPal, Venmo, Cards
  - 25+ currencies
  - 200+ countries
  - Buyer protection
  - Recurring billing
  
Adyen:
  - Cards, Local methods, Wallets
  - 150+ currencies
  - Global enterprise
  - Unified commerce
  - Risk management
  
Square:
  - Cards, Cash App
  - Multiple currencies
  - Integrated POS
  - Invoice features
  - Subscription APIs
  
Authorize.net:
  - Cards, eChecks
  - USD primary
  - US/Canada focus
  - Recurring billing
  - Fraud prevention
  
Worldpay (FIS):
  - Cards, APMs
  - 120+ currencies
  - Enterprise scale
  - Global acquiring
  - Tokenization
  
Checkout.com:
  - Cards, APMs, Wallets
  - 150+ currencies
  - Global coverage
  - Unified API
  - Smart routing
```

#### Regional Specialists (9 providers)
```yaml
Mollie (Europe):
  - iDEAL, SEPA, Cards
  - European methods
  - Multi-currency
  - Recurring payments
  
Razorpay (India):
  - UPI, Cards, Wallets
  - INR primary
  - Indian banking
  - Subscription billing
  
Mercado Pago (LATAM):
  - Local cards, Cash
  - LATAM currencies
  - Installments
  - QR payments
  
Flutterwave (Africa):
  - Mobile money, Cards
  - African currencies
  - M-Pesa, Bank
  - Multi-channel
  
Alipay (China):
  - Alipay wallet
  - CNY primary
  - QR codes
  - Cross-border
  
WeChat Pay (China):
  - WeChat wallet
  - CNY primary
  - In-app payments
  - QR codes
  
Paytm (India):
  - Wallet, UPI, Cards
  - INR focused
  - QR payments
  - Subscriptions
  
iDEAL (Netherlands):
  - Bank transfers
  - EUR only
  - Instant confirmation
  - High adoption
  
SEPA (Europe):
  - Direct debit
  - EUR only
  - 36 countries
  - B2B supported
```

#### Cryptocurrency Processors (5 providers)
```yaml
Coinbase Commerce:
  - BTC, ETH, USDC, etc.
  - No chargebacks
  - Global reach
  - Self-custody
  
BitPay:
  - Multiple cryptocurrencies
  - Fiat settlements
  - Price stability
  - Invoice tools
  
CoinGate:
  - 70+ cryptocurrencies
  - Lightning Network
  - Fiat conversion
  - API/Plugins
  
NOWPayments:
  - 150+ cryptocurrencies
  - Auto conversion
  - Mass payouts
  - Recurring payments
  
BTCPay Server:
  - Self-hosted
  - No fees
  - Full control
  - Privacy focused
```

#### Buy Now Pay Later (5 providers)
```yaml
Klarna:
  - Split payments
  - Pay later options
  - Global coverage
  - Instant approval
  
Afterpay/Clearpay:
  - Installments
  - No interest
  - Instant approval
  - Young demographics
  
Affirm:
  - Flexible terms
  - 0-36% APR
  - High AOV
  - Transparent terms
  
Sezzle:
  - 4 installments
  - Interest-free
  - Instant decisions
  - Virtual cards
  
PayPal Pay Later:
  - Integrated with PayPal
  - Multiple options
  - Wide acceptance
  - Quick checkout
```

#### Enterprise/B2B Focused (5 providers)
```yaml
Bill.com:
  - AP/AR automation
  - ACH, Cards, Checks
  - Approval workflows
  
Paddle:
  - Merchant of Record
  - Tax handling
  - Global compliance
  - SaaS optimized
  
2Checkout (Verifone):
  - Global payments
  - 200+ countries
  - Multiple currencies
  
FastSpring:
  - Digital goods
  - Global tax compliance
  - Subscription management
  
Zuora:
  - Subscription billing
  - Revenue recognition
  - Complex billing
  - Enterprise scale
```

#### Banking & Traditional (4 providers)
```yaml
ACH Direct:
  - US bank transfers
  - Low fees
  - Batch processing
  
Wire Transfer:
  - Global transfers
  - Large amounts
  - Manual processing
  
SWIFT:
  - International wires
  - Bank networks
  - High fees
  
Check/Cheque:
  - Paper or electronic
  - Manual processing
  - Still required (some)
```

#### Mobile & Digital Wallets (6 providers)
```yaml
Apple Pay:
  - iOS integration
  - Touch/Face ID
  - Tokenization
  
Google Pay:
  - Android integration
  - Web support
  - Tokenization
  
Samsung Pay:
  - Samsung devices
  - MST technology
  - Rewards program
  
Amazon Pay:
  - Amazon accounts
  - Voice payments
  - Recurring payments
  
Venmo:
  - US P2P leader
  - Social payments
  - Business profiles
  
Cash App:
  - P2P payments
  - Bitcoin support
  - Cash Card
```

#### Alternative & Niche (6 providers)
```yaml
Paysafecard:
  - Prepaid vouchers
  - Cash-based
  - Anonymous
  
Skrill:
  - Digital wallet
  - 40+ currencies
  - Gaming focus
  
Neteller:
  - E-wallet
  - Instant transfers
  - Prepaid card
  
PaySera:
  - Baltic/EU focus
  - Low fees
  - Multiple currencies
  
Payoneer:
  - Cross-border
  - Mass payouts
  - Multi-currency
  
Wise (TransferWise):
  - Multi-currency accounts
  - Real exchange rates
  - International transfers
```

### Provider Configuration Interface

**Web-based configuration with integrated setup guidance**:

```
Payment Provider Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Available Providers:
├── Stripe [Disabled] [Configure]
├── PayPal [Disabled] [Configure]
├── Square [Disabled] [Configure]
├── [Show all 47+ providers...]

Provider: Stripe
Status: ○ Disabled ● Enabled

[?] Setup Guide ──────────────────────────────
│ 1. Login to dashboard.stripe.com
│ 2. Navigate to Developers → API Keys
│ 3. Copy your keys (use Test mode first)
│ 4. For webhooks: Developers → Webhooks
│ 5. Add endpoint: [your-domain]/webhooks/stripe
│ 6. Select events: payment_intent.*, subscription.*
│ 7. Copy webhook signing secret
│ Need an account? [Create Stripe Account ↗]
└───────────────────────────────────────────────

Configuration:
├── Environment: [Test ▼] [?] Always start with Test mode
│
├── Publishable Key: [___________] 
│   [?] Starts with pk_test_ or pk_live_
│   Found in: Stripe Dashboard → API Keys
│
├── Secret Key: [___________]
│   [?] Starts with sk_test_ or sk_live_ 
│   ⚠️ Never share or expose this key
│   Found in: Stripe Dashboard → API Keys
│
├── Webhook Secret: [___________]
│   [?] Starts with whsec_
│   Found in: Webhooks → Signing secret
│   Required for: Secure webhook validation
│
├── Supported Methods: 
│   ☑ Cards [?] Credit/debit cards
│   ☑ Bank [?] ACH (US), SEPA (EU)
│   ☑ Wallets [?] Apple Pay, Google Pay
│
├── Auto-retry: ☑ Enabled
│   [?] Stripe Smart Retries use ML to optimize timing
│
└── Priority: [1] (for failover)
    [?] Order for payment routing (1 = highest)

[Test Connection] [Save] [Disable]

Connection Test Results:
✓ API Authentication successful
✓ Webhook endpoint reachable
✓ Test charge simulation passed
✗ Webhook signature invalid [Fix?]
```

### Provider Abstraction Layer

```
Interface PaymentProvider {
  // Core methods all providers must implement
  - validate_credentials()
  - get_capabilities()
  - is_available()
  
  // Payment operations
  - tokenize_payment_method()
  - validate_payment_method()
  - authorize_payment()
  - capture_payment()
  - void_authorization()
  - refund_payment()
  
  // Recurring operations (if supported)
  - create_subscription()
  - update_subscription()
  - cancel_subscription()
  - pause_subscription()
  - resume_subscription()
  
  // Query operations
  - get_transaction()
  - get_payment_status()
  - list_transactions()
  - get_balance()
  
  // Webhook handling
  - validate_webhook()
  - process_webhook()
  
  // Compliance (if applicable)
  - verify_customer()
  - report_transaction()
}
```

### Payment Processing Flow

#### Authorization & Capture
```
1. VALIDATE: Check payment method validity
2. CALCULATE: Determine amount including tax
3. SELECT: Choose provider from enabled pool
4. AUTHORIZE: Reserve funds
5. GENERATE: Create invoice
6. CAPTURE: Collect payment
7. CONFIRM: Update records
8. NOTIFY: Send confirmations
```

#### Provider Selection Logic
```
1. Check enabled providers only
2. Filter by capability requirements
3. Apply user preference (if set)
4. Check provider health status
5. Consider geographic optimization
6. Evaluate transaction costs
7. Apply business rules
8. Use priority order for tiebreaking
9. Implement round-robin for load distribution
10. Fall back through priority chain on failure
```

#### Retry Logic with Provider Failover
```yaml
Attempt 1: Primary provider
Attempt 2: Next provider (+1 day)
Attempt 3: Next available (+3 days)  
Attempt 4: Any provider (+5 days)
Attempt 5: Manual/Invoice (+7 days)
Then: Enter suspension
```

### Refunds & Disputes

#### Refund Types
1. **FULL_REFUND**: Complete reversal
2. **PARTIAL_REFUND**: Partial amount
3. **CREDIT_REFUND**: Account credit instead
4. **PRORATION_REFUND**: Plan change adjustment

#### Dispute/Chargeback Handling
```
DISPUTE_CREATED:
  - Freeze subscription changes
  - Gather transaction evidence
  - Notify administrators
  - Check provider for details
  
DISPUTE_UNDER_REVIEW:
  - Submit evidence to provider
  - Continue service (configurable)
  - Monitor status
  
DISPUTE_WON:
  - Restore normal status
  - Log resolution
  
DISPUTE_LOST:
  - Apply refund
  - Review account standing
  - Possible termination
```

---

## 📊 Usage Metering & Limits

### Metering Architecture

#### Meter Types
```yaml
Counter Meters:
  - API calls
  - Transactions
  - Events
  
Gauge Meters:
  - Current storage used
  - Active connections
  - Concurrent users
  
Histogram Meters:
  - Response times
  - Bandwidth usage
  - Processing time
```

#### Measurement Points
```
Application Layer:
  - Feature usage
  - API endpoints
  - User actions
  
Infrastructure Layer:
  - Resource consumption
  - Storage usage
  - Compute time
  
Business Layer:
  - Transactions
  - Documents
  - Operations
```

### Usage Tracking

#### Data Model
```
Usage Record:
  - Account ID
  - Meter type
  - Timestamp
  - Value
  - Dimensions (tags/labels)
  - Aggregation period
  - Billing period
  - State (included|overage|exempt)
```

#### Aggregation Rules
```
Hourly: Real-time monitoring
Daily: User-facing dashboards
Weekly: Trend analysis
Monthly: Billing calculations
Custom: Specific requirements
```

#### Reset Policies
```
HARD_RESET: Zero at period start
ROLLING_WINDOW: Continuous window
CARRY_FORWARD: Unused carries over
ACCUMULATING: Never resets
```

### Enforcement

#### Limit Types
```
Hard Limit:
  IF current_usage >= limit THEN
    DENY request
    RETURN limit_exceeded error
    LOG enforcement event
    
Soft Limit:
  IF current_usage >= limit THEN
    ALLOW request
    TRACK overage
    FLAG for billing
    
Burst Limit:
  IF current_usage >= limit AND burst_tokens > 0 THEN
    ALLOW request
    DECREMENT burst_tokens
    SCHEDULE token refresh
```

### Overage Handling

#### Overage Policies
1. **BLOCK**: Hard stop at limit
2. **ALLOW_WITH_CHARGE**: Continue with fees
3. **ALLOW_WITH_WARNING**: Grace amount then block
4. **AUTO_UPGRADE**: Upgrade to next tier
5. **THROTTLE**: Reduce rate/performance

#### Overage Billing
```
Per-Unit Overage:
  - $X per unit over limit
  - Billed next cycle
  
Tiered Overage:
  - First 10% over: $X per unit
  - Next 20% over: $Y per unit
  - Beyond: $Z per unit
  
Block Overage:
  - Purchase blocks of units
  - Immediate payment required
```

---

## 🏛️ Tax Compliance

### Tax Calculation

#### Tax Types Supported
- **VAT**: Value Added Tax (EU, UK, etc.)
- **GST**: Goods & Services Tax (AU, NZ, IN, etc.)
- **Sales Tax**: State/Local (US, CA)
- **Digital Services Tax**: Various jurisdictions
- **Withholding Tax**: B2B scenarios
- **Custom Taxes**: Jurisdiction-specific

#### Calculation Flow
```
1. DETERMINE: Customer location
2. CLASSIFY: Product/service type
3. CHECK: Exemptions/thresholds
4. LOOKUP: Current tax rate
5. CALCULATE: Tax amount
6. VALIDATE: Business rules
7. DOCUMENT: For compliance
```

### Tax Determination

#### Location Detection
```
Priority Order:
1. Tax registration address
2. Billing address
3. IP geolocation (supplementary)
4. Payment method country
5. Default jurisdiction
```

#### B2B vs B2C
```
B2B Detection:
  - Valid tax ID provided
  - Verification passed
  - Business address confirmed
  
B2B Treatment:
  - Reverse charge (EU)
  - Tax exempt (some jurisdictions)
  - Different rates (some products)
  
B2C Treatment:
  - Full tax applied
  - Simplified invoicing
  - Consumer protections
```

### Compliance Features

#### Tax ID Validation
```
EU VAT: VIES API check
UK VAT: HMRC verification  
US EIN: Format validation
AU ABN: ABR lookup
IN GST: GSTIN verification
[Validation includes tooltips for each]
```

#### Threshold Monitoring
```
Per-Jurisdiction Tracking:
  - Sales volume
  - Transaction count
  - Customer count
  
When threshold approaching:
  - Alert administrators
  - Show guidance in UI
  - Update tax logic
```

### Tax Provider Integration

#### Provider Abstraction
```
Interface TaxProvider {
  - calculate_tax()
  - validate_tax_id()
  - get_rates()
  - file_return() (optional)
  - get_nexus_list()
}
```

#### Fallback Handling
```
IF primary_provider_fails THEN
  Try secondary_provider
  ELSE use_cached_rates
  ELSE use_default_rates
  ALWAYS generate_invoice
```

---

## 📄 Invoicing System

### Invoice Generation

#### Invoice Components
```
Header:
  - Invoice number (sequential/unique)
  - Issue date
  - Due date
  - Tax period
  
Seller Details:
  - Legal business name
  - Address
  - Tax registration numbers
  - Contact information (`server.contact.general.*`)
  
Buyer Details:
  - Customer name
  - Billing address
  - Tax ID (if applicable)
  - Purchase order (if required)
  
Line Items:
  - Description
  - Quantity
  - Unit price
  - Discounts
  - Subtotal
  
Tax Section:
  - Tax breakdown by rate
  - Exemption notices
  - Reverse charge notices
  
Totals:
  - Subtotal
  - Tax amounts
  - Grand total
  - Amount paid
  - Balance due
  
Footer:
  - Payment terms
  - Legal notices
  - Custom notes
  - Provider information
```

### Invoice Lifecycle

#### States
```
DRAFT: Being composed
ISSUED: Sent to customer
DUE: Awaiting payment
OVERDUE: Past due date
PROCESSING: Payment in progress
PAID: Fully paid
PARTIAL: Partially paid
DISPUTED: Under dispute
CANCELLED: Voided
REFUNDED: Money returned
```

#### State Transitions
```
DRAFT → ISSUED: Finalize and send
ISSUED → DUE: Due date reached
DUE → OVERDUE: Past grace period
DUE → PROCESSING: Payment initiated
PROCESSING → PAID: Payment confirmed
PROCESSING → DUE: Payment failed
PAID → REFUNDED: Refund processed
* → DISPUTED: Dispute raised
* → CANCELLED: Manually voided
```

### Invoice Numbering

#### Numbering Schemes
```
Sequential: INV-000001, INV-000002
Date-based: 2024-11-001, 2024-11-002
Prefixed: COMPANY-2024-0001
Custom: User-defined pattern
```

### Credit Notes & Adjustments

#### Credit Note Triggers
- Refunds
- Billing errors
- Service credits
- Downgrades
- Cancellations

#### Adjustment Process
```
1. Create credit note
2. Link to original invoice
3. Apply to account or refund
4. Update balances
5. Notify customer
```

---

## 🔄 Provider Management

### Provider Configuration

#### Default State: ALL DISABLED
**Critical**: No payment providers are enabled by default. Each of the 47+ providers must be explicitly configured and enabled through the web interface. The system can run with zero providers enabled (invoice-only mode).

#### Provider States
```
UNCONFIGURED: Provider available but not set up (default for ALL)
TESTING: Credentials added, validating
ACTIVE: Fully operational
DEGRADED: Partial functionality  
MAINTENANCE: Temporarily offline
FAILED: Not operational
DEPRECATED: Being phased out
DISABLED: Administratively turned off
```

#### Web Configuration Interface
```
Provider Management
━━━━━━━━━━━━━━━━━━
[Search providers...]

Categories:
├── Global Processors (7) [All Disabled]
├── Regional Specialists (9) [All Disabled]
├── Cryptocurrencies (5) [All Disabled]
├── Buy Now Pay Later (5) [All Disabled]
├── Enterprise/B2B (5) [All Disabled]
├── Banking/Traditional (4) [All Disabled]
├── Mobile Wallets (6) [All Disabled]
└── Alternative/Niche (6) [All Disabled]

Status Filter:
○ All ● Disabled ○ Enabled ○ Failed

[Provider List]
├── □ Stripe          [Disabled] [Configure]
├── □ PayPal          [Disabled] [Configure]
├── □ Square          [Disabled] [Configure]
└── [Load more...]

Currently Enabled: 0 of 47
```

#### Zero-Provider Mode
```
System can operate with NO providers:
  - Invoice-only billing
  - Manual payment tracking
  - Offline transactions
  - Check/wire processing
  - Credit memo system
  
Limitations without providers:
  - No automatic charging
  - No instant payments
  - Manual reconciliation
  - Limited automation
```

### Provider Enablement Process

#### Step-by-Step Activation
```
1. SELECT provider from disabled list
2. VIEW integrated setup guide
3. ENTER configuration with tooltips
4. TEST connection
5. CONFIGURE options
6. ENABLE provider
```

#### Provider Priority System
```
Enabled Providers Priority:
1. [Empty - no providers enabled]
2. [Configure providers first]

After enabling:
1. [Stripe]      ↑↓ (drag to reorder)
2. [PayPal]      ↑↓
3. [Square]      ↑↓
```

### Health Monitoring

**Only monitors ENABLED providers**:

#### Monitoring Schedule
```
Every 5 minutes (for enabled only):
  - Ping provider API
  - Check authentication
  - Verify capabilities
  - Update status
  
Disabled providers:
  - No monitoring
  - No API calls
  - No resource usage
```

### Failover & Recovery

#### Failover Strategy
```
When primary provider fails:
  Check next ENABLED provider in priority
  IF found THEN
    Route to next provider
    Log failover event
  ELSE IF manual_mode_configured THEN
    Switch to invoice-only
  ELSE
    Enter grace period mode
```

### Provider Migration

#### Adding New Provider
```
1. Provider appears in DISABLED list
2. No immediate impact
3. Configure when ready
4. Test thoroughly
5. Enable gradually
6. Monitor closely
```

#### Removing Provider
```
1. Disable provider first
2. Migrate active subscriptions
3. Update payment methods
4. Process final webhooks
5. Remove configuration
6. Archive audit logs
```

---

## 📚 Integrated Help System

### Contextual Tooltips

#### Tooltip Types
```
Information [?]:
  - Field descriptions
  - Value formats
  - Examples
  - Best practices
  
Warning [⚠️]:
  - Security alerts
  - Irreversible actions
  - Compliance notes
  - Cost implications
  
Error [❌]:
  - What went wrong
  - How to fix it
  - Alternative options
  - Support contact (`server.contact.general.email`)
  
Success [✓]:
  - What worked
  - Next steps
  - Optimization tips
```

#### Tooltip Content Structure
```
Each tooltip includes:
  1. Brief explanation (1 line)
  2. Detailed description
  3. Where to find (in provider dashboard)
  4. Example values
  5. Common mistakes
  6. Security warnings (if applicable)
  7. Direct link to provider page
```

### Provider Setup Guides

#### Built-in Guide Examples

**Stripe Setup Guide**:
```
[?] Setup Guide ──────────────────────────────
│ 1. Login to dashboard.stripe.com
│ 2. Navigate to Developers → API Keys
│ 3. Copy your keys (use Test mode first)
│ 4. For webhooks: Developers → Webhooks
│ 5. Add endpoint: [your-domain]/webhooks/stripe
│ 6. Select events: payment_intent.*, subscription.*
│ 7. Copy webhook signing secret
│ Need an account? [Create Stripe Account ↗]
└───────────────────────────────────────────────
```

**Regional Provider Example (Razorpay)**:
```
[?] Setup Guide ──────────────────────────────
│ 1. Sign up at razorpay.com
│ 2. Complete KYC verification
│ 3. Dashboard → Settings → API Keys
│ 4. Generate test/live keys
│ Required Documents:
│ • PAN Card
│ • Business registration
│ • Bank account details
│ • GST registration (if applicable)
└───────────────────────────────────────────────
```

### Self-Service Troubleshooting

#### Diagnostic Tools
```
Connection Debugger:
  - Test API credentials
  - Verify webhook endpoints
  - Check network connectivity
  - Validate SSL certificates
  - Test payment flow
  - Simulate common errors
  
Each test shows:
  - What it's checking
  - Why it matters
  - Pass/fail result
  - Fix instructions
```

#### Solution Wizard
```
Problem: Payment failing
├── Is it all payments? [Y/N]
├── Specific card types? [Y/N]
├── Certain amounts? [Y/N]
└── Generate diagnosis

Suggested Solutions:
1. Check 3DS settings [How?]
2. Verify currency support [Check]
3. Review fraud rules [Open]
```

### Interactive Tutorials

#### Guided Setup
```
First Provider Setup:
━━━━━━━━━━━━━━━━━━━
Welcome! Let's set up payments.
This wizard will guide you through:
  
1. Choosing a provider [2 min]
2. Creating provider account [5 min]
3. Configuring credentials [3 min]
4. Testing the connection [2 min]
5. Enabling the provider [1 min]

[Start Interactive Tutorial]
[Skip - I know what I'm doing]
```

#### Provider Comparison Tool
```
Provider Comparison
━━━━━━━━━━━━━━━━━━
Compare: [Stripe] vs [PayPal] vs [Square]

                    Stripe | PayPal | Square
Setup Difficulty      Easy | Medium | Easy
                      [?]  |  [?]   |  [?]
Transaction Fees      2.9% | 2.99%  | 2.6%
                      [?]  |  [?]   |  [?]
International         ✓    |   ✓    |   ✗
                      [?]  |  [?]   |  [?]
```

### Knowledge Base Integration

#### Embedded Documentation
```
Each provider includes:
  - API documentation excerpts
  - Webhook event catalog
  - Error code dictionary
  - Test card numbers
  - Sandbox accounts
  - Rate limits
  - Feature matrix
  - Pricing calculator
```

---

## 📬 Notification System

### Notification Types

#### Transactional Notifications
**Must Send** (Legal/Operational):
- Payment receipts
- Invoice delivery
- Failed payment notices
- Service suspension warnings
- Terms of service changes
- Price changes (advance notice)
- Provider unavailability (if affecting payment)

**Should Send** (User Experience):
- Trial ending reminders
- Renewal reminders
- Usage warnings
- Payment method expiring
- New features available
- Provider restored

#### Marketing Communications
**Opt-in Required**:
- Promotional offers
- Upgrade suggestions
- Newsletter content
- Survey requests

### Delivery Channels

#### Email
```
Templates:
  - HTML with text fallback
  - Localization support
  - Variable substitution
  - Attachment support
  - Provider-specific notices
  
Delivery:
  - Provider abstraction
  - Bounce handling
  - Unsubscribe management
  - SPF/DKIM/DMARC compliance
```

#### In-Application
```
Types:
  - Banner notifications
  - Modal alerts
  - Badge indicators
  - Toast messages
  - Provider status updates
  
Persistence:
  - Until acknowledged
  - Time-based expiry
  - Priority queuing
```

#### Webhooks
```
Events:
  - All billing events
  - Provider state changes
  - Configurable filtering
  - Retry on failure
  - Exponential backoff
  
Security:
  - HMAC signatures
  - TLS required
  - IP whitelist optional
```

### Notification Rules

#### Timing Rules
```
Renewal Reminder:
  - 30 days before (annual)
  - 7 days before (monthly)
  - 1 day before (all)
  
Payment Failure:
  - Immediately
  - Daily during grace
  - Provider switch notice
  - Final warning
  
Provider Failure:
  - After 24 hours
  - Include alternatives
  - Recovery notices
```

---

## 🎮 User Self-Service

### Account Management

#### Available Actions
```
Subscription Management:
  - View current plan
  - Upgrade/downgrade
  - Add/remove features
  - Cancel subscription
  - Pause subscription
  - Resume subscription
  
Payment Management:
  - Add payment method [with provider selection]
  - Remove payment method
  - Set default method
  - Switch payment provider
  - Update billing address
  - View payment history
  - See which provider processed payment
  
Invoice Management:
  - View invoices
  - Download PDF/CSV
  - Email copies
  - Dispute charges
  - Request credit
```

#### Self-Service Flows

**Plan Change Flow**:
```
1. SELECT new plan
2. REVIEW changes
   - Feature comparison
   - Price difference
   - Proration preview
   - Provider compatibility check
3. CONFIRM change
4. PROCESS payment (through enabled providers)
5. APPLY changes
6. SEND confirmation
```

**Provider Selection Flow**:
```
1. VIEW available providers (enabled only)
2. COMPARE features [with tooltips]
3. SELECT preferred provider
4. ENTER payment details
5. VERIFY with provider
6. SET as default (optional)
```

### Usage Dashboard

#### Metrics Display
```
Current Period:
  - Usage by meter
  - Remaining quota
  - Overage tracking
  - Cost to date
  - Provider processing fees
  
Historical:
  - Trend graphs
  - Period comparison
  - Provider distribution
  - Export capability
```

---

## 👨‍💼 Administrative Controls

### Dashboard Overview

#### Key Metrics
```
Revenue Metrics:
  - MRR/ARR
  - Growth rate
  - Churn rate
  - ARPU
  - LTV
  
Operational Metrics:
  - Active subscriptions
  - Trial conversions
  - Payment success rate (per provider)
  - Average payment retry
  - Dispute rate
  
System Health:
  - Provider status (X of 47 enabled)
  - Active providers health
  - Queue depths
  - Error rates
  - Processing times
```

### Provider Management

#### Provider Administration
```
Quick Stats:
  - Total Available: 47 providers
  - Currently Enabled: 0 (default)
  - Healthy: N/A
  - Degraded: N/A
  - Failed: N/A
  
Provider Actions:
  - Browse all providers [with categories]
  - Enable/disable providers
  - Configure credentials [with guides]
  - Test connections
  - Set priorities
  - View provider logs
  - Monitor health
  - Configure webhooks
```

#### Provider Configuration Panel
```
Provider Setup Wizard:
━━━━━━━━━━━━━━━━━━━━━
Step 1: Choose Provider
  [Dropdown: Select from 47 providers]
  [?] Each provider has complete setup guide
  
Step 2: Enter Credentials
  Environment: [Test|Live]
  [?] Always test first, then switch to live
  API Key: [____________]
  [?] Hover for provider-specific instructions
  Secret: [_____________]
  [?] This is sensitive - never share!
  
Step 3: Configure Features
  ☑ Credit Cards [?] Requirements and fees
  ☑ Bank Transfers [?] Clearing times
  ☐ Cryptocurrency [?] Volatility warning
  
Step 4: Test Connection
  [Run Test]
  [?] This performs multiple validation checks
  ✓ Authentication successful
  ✓ API responding
  ✗ Currency issue [?] Click for solution
  
Step 5: Enable
  Priority: [1]
  [?] Determines failover order (1=highest)
  [Enable Provider]
```

### Financial Controls

#### Payment Provider Analytics
```
Provider Performance (Enabled Only):
  - Success rate by provider
  - Average processing time
  - Cost per transaction
  - Failure reasons
  - Geographic performance
  
Provider Costs:
  - Transaction fees
  - Monthly fees
  - Currency conversion
  - Dispute costs
  - Total cost by provider
```

### System Configuration

#### Global Billing Settings
```
Billing Configuration
━━━━━━━━━━━━━━━━━━━
Core Settings:
├── Base Currency: [USD ▼]
├── Multi-currency: [Enabled]
├── Invoice Prefix: [INV-]
├── Tax Engine: [Disabled ▼]
└── Billing Cycle: [Monthly ▼]

Provider Settings:
├── Enabled Providers: 0 of 47 [Configure]
├── Failover: [Automatic ▼]
├── Load Balancing: [Priority ▼]
└── Provider Timeout: [30] seconds

Features:
☑ Multiple Payment Methods
☑ Automatic Retry
☑ Grace Periods
☐ Cryptocurrency (no crypto provider enabled)
☐ BNPL Options (no BNPL provider enabled)
☑ Manual Invoicing (always available)
```

---

## 🔐 Security & Compliance

### Data Protection

#### Sensitive Data Handling
```
Payment Data:
  - Never store full card numbers
  - Tokenization required
  - Provider handles PCI compliance
  - Encryption at rest
  - Encryption in transit
  
Personal Data:
  - GDPR compliance
  - Data minimization
  - Purpose limitation
  - Retention policies
  - Right to deletion
```

#### Access Controls
```
Role-Based Access:
  - Granular permissions
  - Separation of duties
  - Audit logging
  - Session management
  - MFA enforcement
  - Provider credential protection
```

### PCI Compliance

#### Compliance Levels
```
Level 1: >6M transactions/year
Level 2: 1M-6M transactions/year  
Level 3: 20K-1M transactions/year
Level 4: <20K transactions/year

Note: Most providers handle PCI compliance
```

### Regulatory Compliance

#### Regional Requirements
```
Europe (GDPR):
  - Explicit consent
  - Data portability
  - Right to deletion
  - Privacy by design
  
California (CCPA):
  - Disclosure requirements
  - Opt-out rights
  - Non-discrimination
  
Industry-Specific:
  - HIPAA (healthcare)
  - SOC2 (enterprise)
  - ISO 27001 (international)
```

### Audit Requirements

#### Audit Logging
```
What to Log:
  - All state changes
  - Payment attempts (with provider)
  - Administrative actions
  - Provider configuration changes
  - API access
  - Security events
  
Log Contents:
  - Timestamp
  - Actor (user/system)
  - Action
  - Target
  - Provider used
  - Result
  - IP address
```

---

## 🚨 Failure Handling & Recovery

### Provider Failures

#### Detection
```
Health Check Failed:
  - Immediate retry
  - Mark degraded after 3 failures
  - Mark failed after 5 failures
  - Try next provider in priority
  
API Error:
  - Check error type
  - Temporary vs permanent
  - Update provider status
  - Failover if needed
```

#### Response Strategy
```
Payment Provider Down:
  IF alternate_provider_enabled THEN
    Failover to next in priority
  ELSE IF within_grace_period THEN
    Queue transaction
    Continue service
    Notify user of delay
  ELSE IF manual_invoicing_enabled THEN
    Generate proforma invoice
    Await manual payment
  ELSE
    Enter grace period only mode
    
Tax Provider Down:
  Use cached rates
  Apply default rules
  Flag for review
  Continue operations
```

### Data Recovery

#### Backup Strategy
```
Real-time:
  - Transaction logs
  - State changes
  - Provider events
  - Critical events
  
Daily:
  - Full database
  - Configuration
  - Provider settings
  - Audit logs
  
Retention:
  - Transactions: 7 years
  - Provider logs: 1 year
  - Backups: 90 days
```

### Reconciliation

#### Automatic Reconciliation
```
Hourly:
  - Payment status sync (per provider)
  - Webhook gap detection
  
Daily:
  - Provider transaction match
  - Cross-provider verification
  - Balance verification
  
Weekly:
  - Full audit
  - Discrepancy report
  - Manual review queue
```

---

## 📈 Audit & Reporting

### Financial Reporting

#### Standard Reports
```
Revenue Reports:
  - MRR/ARR breakdown
  - Revenue by plan
  - Revenue by provider
  - Revenue by region
  - Growth trends
  
Transaction Reports:
  - Payment success/failure by provider
  - Provider distribution
  - Refunds and disputes
  - Processing fees per provider
  - Gateway comparison
  
Customer Reports:
  - Acquisition cost
  - Lifetime value
  - Churn analysis
  - Payment method distribution
  - Provider preferences
```

### Compliance Reporting

#### Tax Reports
```
Jurisdiction Reports:
  - Tax collected by region
  - Nexus threshold tracking
  - B2B vs B2C breakdown
  - Exemption summary
  
Filing Reports:
  - Format per jurisdiction
  - Period summaries
  - Supporting documentation
  - Audit trail
```

### Analytics

#### Business Intelligence
```
Metrics Tracked:
  - Customer acquisition cost
  - Revenue per customer
  - Provider performance
  - Feature adoption
  - Usage patterns
  - Conversion funnels
  
Provider Analytics:
  - Success rates comparison
  - Cost efficiency
  - Geographic performance
  - Failure analysis
```

---

## 🔌 Integration Points

### Required Integrations

#### Host Application
```
Data Exchange:
  - User authentication
  - Account provisioning
  - Feature flags
  - Usage data
  - Audit events
  
Synchronization:
  - Real-time status
  - Provider availability
  - Periodic reconciliation
  - Bulk updates
  - Event streaming
```

#### External Services
```
Payment Providers (47+ available):
  - All disabled by default
  - Web UI configuration only
  - No hardcoded credentials
  - Plugin architecture
  
Tax Services:
  - API keys via UI
  - Calculation rules
  - Rate updates
  - Filing integration
  
Communication:
  - Email service
  - SMS gateway
  - Push notifications
  - In-app messaging
```

### API Design

#### REST Endpoints (Examples - Implementation Defines Actual)
```
Subscriptions:
  - List subscriptions
  - Create subscription
  - Update subscription
  - Cancel subscription
  
Invoices:
  - List invoices
  - Get invoice details
  - Pay invoice
  - Dispute invoice
  
Providers:
  - List enabled providers
  - Get provider status
  - Test provider
```

#### Webhooks Out
```
Events Emitted:
  - subscription.created
  - subscription.updated
  - payment.succeeded
  - payment.failed
  - invoice.created
  - provider.failed
  - provider.recovered
```

---

## 🤖 AI Development Guidelines (DEVELOPMENT ONLY)

### ⚠️ CRITICAL: AI is for Development, NOT Required in Production

**AI tools are used ONLY during development to:**
- Generate provider integration code
- Create state machine implementations
- Build test scenarios
- Generate tooltip content
- Create migration scripts

**The production system:**
- May or may not use AI/ML (implementation choice)
- All core billing logic is deterministic
- Provider integrations are rule-based
- State transitions are explicit
- No AI required for operation

### Using AI Development Tools

#### Initial Setup with AI
```bash
# Example using Claude Code
$ claude-code "Implement billing system based on specification with:
  - 47+ payment providers (all disabled by default)
  - Web UI configuration only
  - Provider plugin architecture
  - Complex state machines
  - Integrated help system"
```

#### AI-Generated Provider Plugins
```bash
# Generate provider implementation
$ claude-code "Create Stripe provider plugin including:
  - Interface implementation
  - Webhook handling
  - Error mapping
  - Retry logic
  - Tooltip content
  - Setup guide"

# Generate all provider stubs
$ claude-code "Generate plugin stubs for all 47 providers"
```

#### State Machine Implementation
```bash
$ claude-code "Generate subscription state machine:
  - All states from spec
  - Transition validation
  - Event handling
  - Test coverage"
```

#### Test Generation
```bash
$ claude-code "Create comprehensive test suite:
  - Provider failover scenarios
  - Grace period handling
  - Multi-currency calculations
  - All state transitions
  - Webhook processing"
```

### What AI Generates

#### Per-Provider Components
- Payment method tokenization
- Subscription management
- Webhook event handling
- Error code mapping
- Currency handling
- Retry logic
- Test data
- Setup documentation
- Tooltip content

#### System Components
- State machines
- Proration calculations
- Tax calculation logic
- Failover routing
- Reconciliation processes
- Migration scripts
- Database schemas

### AI Development Best Practices

**DO:**
- Use AI to generate provider plugins from templates
- Have AI create comprehensive test suites
- Let AI generate tooltip and help content
- Use AI for migration scripts
- Generate documentation with AI

**DON'T:**
- Rely on AI for financial calculations in production
- Use AI for real-time payment decisions
- Let AI generate security credentials
- Use AI for compliance decisions
- Generate production API keys with AI

**VALIDATE:**
- All state machines match specification
- Provider interfaces are complete
- Error handling is comprehensive
- Security requirements are met
- Help content is accurate

### Production Considerations

**What happens in production:**
- All provider plugins run as deterministic code
- State machines execute predefined transitions
- Calculations follow explicit formulas
- Failover uses configured priority
- No AI required for any billing operation

**Optional AI/ML in Production** (Implementation Choice):
- Fraud detection (separate from billing logic)
- Churn prediction (analytics layer)
- Optimal retry timing (enhancement only)
- Revenue forecasting (reporting feature)
- These are OPTIONAL additions, not requirements

---

## 💡 Implementation Guidelines

### Architecture Patterns

#### Recommended Patterns
```
Event-Driven:
  - All state changes emit events
  - Async processing where possible
  - Event sourcing for audit
  
Microservices:
  - Billing as separate service
  - Clear API boundaries
  - Independent scaling
  
Plugin Architecture:
  - Each provider as plugin
  - Dynamic loading
  - Interface compliance
```

#### Anti-Patterns to Avoid
```
DON'T:
  - Store sensitive payment data directly
  - Hard-code provider credentials
  - Put provider credentials anywhere other than `secrets.yml`
  - Enable providers by default
  - Skip tooltip implementation
  - Make synchronous external calls in transactions
  - Allow financial operations without audit
  - Trust client-side calculations
  - Store API keys in code
```

### Provider Implementation

#### Provider Plugin Architecture
```
Each provider should be:
  - Self-contained module/plugin
  - Dynamically loadable
  - Configuration-driven
  - Interface compliant
  - Independently testable
  - Include help content
  
Provider Directory Structure (example):
  /providers
    /stripe
      - provider.js (implements interface)
      - config.schema.json
      - webhook.handler.js
      - tooltips.json (help content)
      - tests.js
    /paypal
      - (same structure)
    [... 45 more providers]
```

#### Provider Registry
```
System maintains registry of:
  - Available providers (all 47+)
  - Enabled providers (user configured)
  - Provider capabilities
  - Provider health status
  - Provider configuration
  - Help content per provider
  
No provider code runs unless:
  - Explicitly enabled via web UI
  - Configuration validated
  - Credentials verified
  - Tests passed
```

#### Configuration Storage
```
Provider configurations stored in:
  - `secrets.yml` (mode 0600, never committed)
  - Never in code
  - Written by the admin UI
  - Billing API keys live in the single hashed `tokens` table
  - Audited on every change
  - Includes tooltip content
```

### Testing Strategy

#### Test Coverage Required
```
Unit Tests:
  - Calculation logic
  - State transitions
  - Business rules
  - Each provider plugin
  
Integration Tests:
  - Provider interactions
  - Webhook processing
  - API endpoints
  - Failover scenarios
  
End-to-End Tests:
  - Complete billing cycles
  - Provider switching
  - Upgrade/downgrade flows
  - Payment failure handling
  
Performance Tests:
  - High volume processing
  - Multiple provider load
  - Concurrent operations
  - Rate limiting
```

### Migration Strategy

#### From Existing System
```
Phase 1: Read-only mode
  - Import existing data
  - Map to new structure
  - Verify accuracy
  - Run in parallel
  
Phase 2: New customers only
  - Test with subset
  - Use limited providers
  - Monitor closely
  - Fix issues
  
Phase 3: Gradual migration
  - Migrate by cohort
  - Enable providers gradually
  - Maintain old system
  - Provide rollback
  
Phase 4: Full cutover
  - Migrate remaining
  - Enable all needed providers
  - Decommission old
  - Archive data
```

---

## 📋 Appendix

### State Diagrams

#### Complete Subscription State Machine
```
[PENDING_ACTIVATION] → [TRIALING] → [ACTIVE] → [PAST_DUE] → [CANCELLED] → [EXPIRED]
         ↓                ↓           ↓           ↓            ↓
     [ACTIVE]        [CANCELLED]  [PAUSED]  [SUSPENDED]   [EXPIRED]
```

#### Invoice State Machine
```
[DRAFT] → [ISSUED] → [DUE] → [PROCESSING] → [PAID]
             ↓         ↓          ↓           ↓
        [CANCELLED] [OVERDUE] [FAILED]   [REFUNDED]
```

#### Payment State Machine
```
[INITIATED] → [AUTHORIZED] → [CAPTURED] → [SETTLED]
      ↓            ↓             ↓           ↓
  [FAILED]    [CANCELLED]   [REFUNDED]  [DISPUTED]
```

#### Provider State Machine
```
[UNCONFIGURED] → [TESTING] → [ACTIVE] → [DEGRADED] → [FAILED]
       ↓             ↓           ↓          ↓           ↓
  [DISABLED]    [DISABLED]  [MAINTENANCE] [DISABLED] [DISABLED]
```

### Error Codes

#### Standard Billing Error Codes
```
BILLING-001: Invalid payment method
BILLING-002: Insufficient funds
BILLING-003: Card declined
BILLING-004: Subscription not found
BILLING-005: Plan not available
BILLING-006: Tax calculation failed
BILLING-007: Provider unavailable
BILLING-008: Duplicate transaction
BILLING-009: Rate limit exceeded
BILLING-010: Invalid tax ID
BILLING-011: No providers enabled
BILLING-012: All providers failed
```

### Glossary

- **MRR**: Monthly Recurring Revenue
- **ARR**: Annual Recurring Revenue
- **ARPU**: Average Revenue Per User
- **LTV**: Lifetime Value
- **CAC**: Customer Acquisition Cost
- **Churn**: Subscription cancellation rate
- **Dunning**: Failed payment recovery process
- **Proration**: Partial period billing calculation
- **Grace Period**: Time allowed after payment failure
- **Webhook**: HTTP callback for events
- **Tokenization**: Secure payment data storage
- **PCI DSS**: Payment Card Industry Data Security Standard
- **SCA**: Strong Customer Authentication
- **3DS**: 3D Secure authentication
- **KYC**: Know Your Customer
- **AML**: Anti-Money Laundering
- **BNPL**: Buy Now Pay Later
- **APM**: Alternative Payment Method

### Provider Quick Reference

#### Categories Summary
- **Global Processors**: 7 providers (Stripe, PayPal, Adyen, etc.)
- **Regional Specialists**: 9 providers (Mollie, Razorpay, etc.)
- **Cryptocurrency**: 5 providers (Coinbase Commerce, BitPay, etc.)
- **Buy Now Pay Later**: 5 providers (Klarna, Afterpay, etc.)
- **Enterprise/B2B**: 5 providers (Bill.com, Paddle, etc.)
- **Banking/Traditional**: 4 providers (ACH, Wire, etc.)
- **Mobile Wallets**: 6 providers (Apple Pay, Google Pay, etc.)
- **Alternative/Niche**: 6 providers (Paysafecard, Skrill, etc.)

**Total Available**: 47+ providers
**Default Enabled**: 0 providers
**Configuration Method**: Admin UI writes `secrets.yml`

### Version History

- v2.1 - Complete regeneration with all 47+ providers, integrated help, AI development section
- v2.0 - Added provider management, help system, state machines
- v1.0 - Initial specification

---

## 📝 Critical Implementation Notes

1. **All Payment Providers Disabled by Default**: System ships with 47+ provider integrations, ALL disabled
2. **Credentials in secrets.yml Only**: Provider credentials NEVER in code or committed files; the admin UI writes `secrets.yml` (mode 0600)
3. **Integrated Help Required**: All provider setup instructions must be in-UI with tooltips
4. **Never Store Sensitive Payment Data**: Always use tokenization
5. **Always Generate Invoices**: Even if payment fails or all providers are down
6. **Grace Periods Are Required**: Never immediately terminate on payment failure
7. **Audit Everything**: Every financial operation must be logged
8. **Provider Independence**: System must work with zero providers enabled (invoice-only mode)
9. **Tax Compliance Is Not Optional**: Must support international tax requirements
10. **Idempotency Is Mandatory**: Prevent duplicate charges across all providers
11. **Reconciliation Is Critical**: Daily reconciliation per provider required
12. **User Control**: Clear cancellation and data export required
13. **Testing With Real Money**: Production-like testing environment required
14. **Provider Failover**: Automatic failover through enabled providers only
15. **No Provider Lock-in**: Must be able to migrate between providers
16. **Plugin Architecture**: Each provider is a self-contained module
17. **AI for Development Only**: AI assists development but is NOT required for production
18. **Help Content Mandatory**: Every configuration field must have contextual help
19. **Zero-Provider Operation**: System must function with manual invoicing only
20. **Provider Priority**: Failover follows admin-configured priority order

---

*This specification is designed to be completely implementation-agnostic and can be adapted to any technology stack, business model, or deployment environment. The billing system should integrate with your existing application while maintaining clear boundaries and separation of concerns.*

*All 47+ payment providers are available but disabled by default. Configuration is done exclusively through the web UI with integrated help and tooltips. No external documentation is required for provider setup.*

*AI tools can assist in development but are not required for production operation. The core billing logic is deterministic and does not require any machine learning or AI to function.*
