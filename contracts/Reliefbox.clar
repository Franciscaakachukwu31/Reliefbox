(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_ORGANIZATION_NOT_VERIFIED (err u102))
(define-constant ERR_ORGANIZATION_ALREADY_VERIFIED (err u103))
(define-constant ERR_ORGANIZATION_NOT_FOUND (err u104))
(define-constant ERR_WITHDRAWAL_FAILED (err u105))
(define-constant ERR_INVALID_AMOUNT (err u106))
(define-constant ERR_EMERGENCY_PAUSED (err u107))

(define-data-var total-donations uint u0)
(define-data-var total-withdrawals uint u0)
(define-data-var contract-paused bool false)
(define-data-var emergency-fund-percentage uint u5)

(define-map verified-organizations principal {
    name: (string-ascii 100),
    verified-at: uint,
    total-received: uint,
    active: bool
})

(define-map donations principal {
    total-donated: uint,
    donation-count: uint,
    first-donation-block: uint
})

(define-map withdrawal-requests principal {
    amount: uint,
    requested-at: uint,
    approved: bool,
    description: (string-ascii 200)
})

(define-map emergency-releases uint {
    recipient: principal,
    amount: uint,
    released-at: uint,
    reason: (string-ascii 200)
})

(define-data-var emergency-release-counter uint u0)

(define-public (donate)
    (let ((donation-amount (stx-get-balance tx-sender)))
        (asserts! (> donation-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get contract-paused)) ERR_EMERGENCY_PAUSED)
        (try! (stx-transfer? donation-amount tx-sender (as-contract tx-sender)))
        (var-set total-donations (+ (var-get total-donations) donation-amount))
        (map-set donations tx-sender {
            total-donated: (+ (get-donation-total tx-sender) donation-amount),
            donation-count: (+ (get-donation-count tx-sender) u1),
            first-donation-block: (match (map-get? donations tx-sender)
                existing-donation (get first-donation-block existing-donation)
                stacks-block-height)
        })
        (ok donation-amount)))

(define-public (verify-organization (organization principal) (name (string-ascii 100)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-none (map-get? verified-organizations organization)) ERR_ORGANIZATION_ALREADY_VERIFIED)
        (map-set verified-organizations organization {
            name: name,
            verified-at: stacks-block-height,
            total-received: u0,
            active: true
        })
        (ok true)))

(define-public (revoke-organization (organization principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-some (map-get? verified-organizations organization)) ERR_ORGANIZATION_NOT_FOUND)
        (map-set verified-organizations organization
            (merge (unwrap-panic (map-get? verified-organizations organization))
                {active: false}))
        (ok true)))

(define-public (request-withdrawal (amount uint) (description (string-ascii 200)))
    (let ((org-data (unwrap! (map-get? verified-organizations tx-sender) ERR_ORGANIZATION_NOT_VERIFIED)))
        (asserts! (get active org-data) ERR_ORGANIZATION_NOT_VERIFIED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount (get-available-funds)) ERR_INSUFFICIENT_FUNDS)
        (asserts! (not (var-get contract-paused)) ERR_EMERGENCY_PAUSED)
        (map-set withdrawal-requests tx-sender {
            amount: amount,
            requested-at: stacks-block-height,
            approved: false,
            description: description
        })
        (ok true)))

(define-public (approve-withdrawal (organization principal))
    (let ((request (unwrap! (map-get? withdrawal-requests organization) ERR_ORGANIZATION_NOT_FOUND))
          (org-data (unwrap! (map-get? verified-organizations organization) ERR_ORGANIZATION_NOT_VERIFIED)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (not (get approved request)) ERR_WITHDRAWAL_FAILED)
        (asserts! (get active org-data) ERR_ORGANIZATION_NOT_VERIFIED)
        (let ((withdrawal-amount (get amount request)))
            (try! (as-contract (stx-transfer? withdrawal-amount tx-sender organization)))
            (var-set total-withdrawals (+ (var-get total-withdrawals) withdrawal-amount))
            (map-set verified-organizations organization
                (merge org-data {total-received: (+ (get total-received org-data) withdrawal-amount)}))
            (map-set withdrawal-requests organization
                (merge request {approved: true}))
            (ok withdrawal-amount))))

(define-public (emergency-release (recipient principal) (amount uint) (reason (string-ascii 200)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount (get-available-funds)) ERR_INSUFFICIENT_FUNDS)
        (let ((release-id (+ (var-get emergency-release-counter) u1)))
            (try! (as-contract (stx-transfer? amount tx-sender recipient)))
            (var-set total-withdrawals (+ (var-get total-withdrawals) amount))
            (var-set emergency-release-counter release-id)
            (map-set emergency-releases release-id {
                recipient: recipient,
                amount: amount,
                released-at: stacks-block-height,
                reason: reason
            })
            (ok release-id))))

(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused true)
        (ok true)))

(define-public (unpause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused false)
        (ok true)))

(define-public (set-emergency-fund-percentage (percentage uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= percentage u100) ERR_INVALID_AMOUNT)
        (var-set emergency-fund-percentage percentage)
        (ok true)))

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender)))

(define-read-only (get-total-donations)
    (var-get total-donations))

(define-read-only (get-total-withdrawals)
    (var-get total-withdrawals))

(define-read-only (get-available-funds)
    (- (get-contract-balance) (/ (* (get-contract-balance) (var-get emergency-fund-percentage)) u100)))

(define-read-only (get-emergency-fund)
    (/ (* (get-contract-balance) (var-get emergency-fund-percentage)) u100))

(define-read-only (is-organization-verified (organization principal))
    (match (map-get? verified-organizations organization)
        org-data (get active org-data)
        false))

(define-read-only (get-organization-info (organization principal))
    (map-get? verified-organizations organization))

(define-read-only (get-donation-info (donor principal))
    (map-get? donations donor))

(define-read-only (get-donation-total (donor principal))
    (match (map-get? donations donor)
        donation-data (get total-donated donation-data)
        u0))

(define-read-only (get-donation-count (donor principal))
    (match (map-get? donations donor)
        donation-data (get donation-count donation-data)
        u0))

(define-read-only (get-withdrawal-request (organization principal))
    (map-get? withdrawal-requests organization))

(define-read-only (get-emergency-release (release-id uint))
    (map-get? emergency-releases release-id))

(define-read-only (is-contract-paused)
    (var-get contract-paused))

(define-read-only (get-contract-owner)
    CONTRACT_OWNER)

(define-read-only (get-contract-stats)
    {
        total-donations: (var-get total-donations),
        total-withdrawals: (var-get total-withdrawals),
        current-balance: (get-contract-balance),
        available-funds: (get-available-funds),
        emergency-fund: (get-emergency-fund),
        emergency-fund-percentage: (var-get emergency-fund-percentage),
        contract-paused: (var-get contract-paused),
        emergency-releases-count: (var-get emergency-release-counter)
    })
