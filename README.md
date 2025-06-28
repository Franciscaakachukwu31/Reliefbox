# Reliefbox - Disaster Relief Escrow Contract

A Clarity smart contract that creates a secure escrow system for disaster relief donations, ensuring funds are only released to verified humanitarian organizations.

## Overview

Reliefbox provides a transparent and secure way to collect disaster relief donations and distribute them exclusively to verified aid organizations. The contract includes emergency release mechanisms, donation tracking, and administrative controls to ensure maximum accountability and effectiveness during crisis situations.

## Core Features

- **Secure Donation Collection**: Accept STX donations with automatic tracking
- **Organization Verification**: Admin-controlled verification system for aid organizations  
- **Withdrawal Approval Process**: Two-step withdrawal system with request and approval
- **Emergency Release**: Direct fund release capability for urgent situations
- **Emergency Fund Reserve**: Configurable percentage of funds reserved for emergencies
- **Contract Pause**: Emergency pause functionality to halt all operations
- **Comprehensive Tracking**: Full audit trail of donations, withdrawals, and releases

## Contract Functions

### Public Functions

#### For Donors
- `donate()` - Send STX donations to the contract

#### For Organizations
- `request-withdrawal(amount, description)` - Request funds withdrawal with justification

#### For Contract Owner
- `verify-organization(organization, name)` - Verify a new aid organization
- `revoke-organization(organization)` - Revoke organization verification
- `approve-withdrawal(organization)` - Approve pending withdrawal requests
- `emergency-release(recipient, amount, reason)` - Direct emergency fund release
- `pause-contract()` - Pause all contract operations
- `unpause-contract()` - Resume contract operations
- `set-emergency-fund-percentage(percentage)` - Set emergency fund reserve percentage

### Read-Only Functions

- `get-contract-balance()` - Current contract STX balance
- `get-total-donations()` - Total donations received
- `get-total-withdrawals()` - Total funds withdrawn
- `get-available-funds()` - Funds available for withdrawal (excluding emergency reserve)
- `get-emergency-fund()` - Current emergency fund amount
- `is-organization-verified(organization)` - Check organization verification status
- `get-organization-info(organization)` - Get organization details
- `get-donation-info(donor)` - Get donor statistics
- `get-withdrawal-request(organization)` - Get pending withdrawal request
- `get-emergency-release(release-id)` - Get emergency release details
- `get-contract-stats()` - Complete contract statistics

## Usage Instructions

### Deploy Contract
```bash
clarinet deploy --devnet
```

### Verify Organization (Contract Owner Only)
```bash
clarinet console
> (contract-call? .Reliefbox verify-organization 'SP1ABC...DEF "Red Cross International")
```

### Make Donation
```bash
> (contract-call? .Reliefbox donate)
```

### Request Withdrawal (Verified Organization)
```bash
> (contract-call? .Reliefbox request-withdrawal u1000000 "Emergency medical supplies for earthquake victims")
```

### Approve Withdrawal (Contract Owner)
```bash
> (contract-call? .Reliefbox approve-withdrawal 'SP1ABC...DEF)
```

### Check Contract Status
```bash
> (contract-call? .Reliefbox get-contract-stats)
```

## Error Codes

- `u100` - Unauthorized access
- `u101` - Insufficient funds
- `u102` - Organization not verified
- `u103` - Organization already verified
- `u104` - Organization not found
- `u105` - Withdrawal failed
- `u106` - Invalid amount
- `u107` - Contract paused

## Security Features

- Owner-only administrative functions
- Emergency pause mechanism
- Reserved emergency fund
- Complete audit trail
- Organization verification system
- Two-step withdrawal process

## Testing

Run tests using Clarinet:
```bash
clarinet test
```

## Contract Architecture

The contract maintains separate tracking for:
- Verified organizations with activity status
- Individual donation records per donor
- Withdrawal requests with approval workflow
- Emergency releases with detailed logging
- Contract-level statistics and controls

Emergency fund percentage (default 5%) ensures critical funds remain available for direct emergency releases when immediate response is required.
