(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_ORGANIZATION_NOT_VERIFIED (err u102))
(define-constant ERR_ORGANIZATION_ALREADY_VERIFIED (err u103))
(define-constant ERR_ORGANIZATION_NOT_FOUND (err u104))
(define-constant ERR_WITHDRAWAL_FAILED (err u105))
(define-constant ERR_INVALID_AMOUNT (err u106))
(define-constant ERR_EMERGENCY_PAUSED (err u107))
(define-constant ERR_REWARD_PROCESSING_FAILED (err u108))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u109))
(define-constant ERR_CAMPAIGN_EXPIRED (err u110))
(define-constant ERR_CAMPAIGN_NOT_ACTIVE (err u111))
(define-constant ERR_INSUFFICIENT_MATCHING_FUNDS (err u112))
(define-constant ERR_CAMPAIGN_ALREADY_EXISTS (err u113))
(define-constant ERR_INVALID_CAMPAIGN_PARAMS (err u114))

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

(define-map donor-rewards principal {
    total-points: uint,
    loyalty-tier: uint,
    streak-days: uint,
    last-donation-block: uint,
    achievements: (list 10 uint),
    referral-count: uint,
    bonus-multiplier: uint
})

(define-map achievement-definitions uint {
    name: (string-ascii 50),
    description: (string-ascii 200),
    points-reward: uint,
    requirement-type: (string-ascii 20),
    requirement-value: uint,
    active: bool
})

(define-map donor-referrals principal {
    referrer: principal,
    referred-at: uint,
    bonus-claimed: bool
})

(define-map loyalty-tiers uint {
    name: (string-ascii 30),
    min-points: uint,
    bonus-percentage: uint,
    special-benefits: (string-ascii 100)
})

(define-map matching-campaigns uint {
    name: (string-ascii 100),
    description: (string-ascii 300),
    sponsor: principal,
    target-organization: (optional principal),
    start-block: uint,
    end-block: uint,
    matching-ratio-numerator: uint,
    matching-ratio-denominator: uint,
    max-matching-amount: uint,
    current-matched-amount: uint,
    total-donations-received: uint,
    active: bool,
    created-at: uint
})

(define-map campaign-donations uint {
    campaign-id: uint,
    donor: principal,
    amount: uint,
    matched-amount: uint,
    donated-at: uint
})

(define-map campaign-participant-stats principal {
    total-campaigns-donated: uint,
    total-matched-received: uint,
    favorite-campaign-type: (string-ascii 50)
})

(define-data-var achievement-counter uint u0)
(define-data-var referral-bonus-percentage uint u5)

(define-data-var emergency-release-counter uint u0)
(define-data-var total-reward-points uint u0)
(define-data-var loyalty-tier-threshold uint u1000)
(define-data-var reward-multiplier uint u10)

(define-data-var matching-campaign-counter uint u0)
(define-data-var total-matched-funds uint u0)

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
        (begin
            (unwrap-panic (process-donation-rewards tx-sender donation-amount))
            (ok donation-amount))))

(define-public (donate-with-referral (referrer principal))
    (let ((donation-amount (stx-get-balance tx-sender)))
        (asserts! (> donation-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get contract-paused)) ERR_EMERGENCY_PAUSED)
        (asserts! (not (is-eq tx-sender referrer)) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? donation-amount tx-sender (as-contract tx-sender)))
        (var-set total-donations (+ (var-get total-donations) donation-amount))
        (map-set donations tx-sender {
            total-donated: (+ (get-donation-total tx-sender) donation-amount),
            donation-count: (+ (get-donation-count tx-sender) u1),
            first-donation-block: (match (map-get? donations tx-sender)
                existing-donation (get first-donation-block existing-donation)
                stacks-block-height)
        })
        (if (is-none (map-get? donor-referrals tx-sender))
            (map-set donor-referrals tx-sender {
                referrer: referrer,
                referred-at: stacks-block-height,
                bonus-claimed: false
            })
            true)
        (begin
            (unwrap-panic (process-donation-rewards tx-sender donation-amount))
            (unwrap-panic (process-referral-bonus referrer))
            (ok donation-amount))))

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

(define-public (create-achievement (name (string-ascii 50)) (description (string-ascii 200)) (points-reward uint) (requirement-type (string-ascii 20)) (requirement-value uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (let ((achievement-id (+ (var-get achievement-counter) u1)))
            (var-set achievement-counter achievement-id)
            (map-set achievement-definitions achievement-id {
                name: name,
                description: description,
                points-reward: points-reward,
                requirement-type: requirement-type,
                requirement-value: requirement-value,
                active: true
            })
            (ok achievement-id))))

(define-public (create-loyalty-tier (tier-id uint) (name (string-ascii 30)) (min-points uint) (bonus-percentage uint) (special-benefits (string-ascii 100)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set loyalty-tiers tier-id {
            name: name,
            min-points: min-points,
            bonus-percentage: bonus-percentage,
            special-benefits: special-benefits
        })
        (ok true)))

(define-public (create-matching-campaign 
    (name (string-ascii 100)) 
    (description (string-ascii 300)) 
    (target-organization (optional principal)) 
    (duration-blocks uint) 
    (matching-ratio-numerator uint) 
    (matching-ratio-denominator uint) 
    (max-matching-amount uint))
    (let ((campaign-id (+ (var-get matching-campaign-counter) u1))
          (sponsor-balance (stx-get-balance tx-sender))
          (start-block stacks-block-height)
          (end-block (+ stacks-block-height duration-blocks)))
        (asserts! (> duration-blocks u0) ERR_INVALID_CAMPAIGN_PARAMS)
        (asserts! (> matching-ratio-numerator u0) ERR_INVALID_CAMPAIGN_PARAMS)
        (asserts! (> matching-ratio-denominator u0) ERR_INVALID_CAMPAIGN_PARAMS)
        (asserts! (> max-matching-amount u0) ERR_INVALID_CAMPAIGN_PARAMS)
        (asserts! (>= sponsor-balance max-matching-amount) ERR_INSUFFICIENT_MATCHING_FUNDS)
        (asserts! (not (var-get contract-paused)) ERR_EMERGENCY_PAUSED)
        (match target-organization
            org (asserts! (is-organization-verified org) ERR_ORGANIZATION_NOT_VERIFIED)
            true)
        (try! (stx-transfer? max-matching-amount tx-sender (as-contract tx-sender)))
        (var-set matching-campaign-counter campaign-id)
        (map-set matching-campaigns campaign-id {
            name: name,
            description: description,
            sponsor: tx-sender,
            target-organization: target-organization,
            start-block: start-block,
            end-block: end-block,
            matching-ratio-numerator: matching-ratio-numerator,
            matching-ratio-denominator: matching-ratio-denominator,
            max-matching-amount: max-matching-amount,
            current-matched-amount: u0,
            total-donations-received: u0,
            active: true,
            created-at: stacks-block-height
        })
        (ok campaign-id)))

(define-public (donate-to-campaign (campaign-id uint))
    (let ((campaign (unwrap! (map-get? matching-campaigns campaign-id) ERR_CAMPAIGN_NOT_FOUND))
          (donation-amount (stx-get-balance tx-sender)))
        (asserts! (> donation-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get contract-paused)) ERR_EMERGENCY_PAUSED)
        (asserts! (get active campaign) ERR_CAMPAIGN_NOT_ACTIVE)
        (asserts! (>= stacks-block-height (get start-block campaign)) ERR_CAMPAIGN_NOT_ACTIVE)
        (asserts! (< stacks-block-height (get end-block campaign)) ERR_CAMPAIGN_EXPIRED)
        (match (get target-organization campaign)
            target-org (asserts! (is-organization-verified target-org) ERR_ORGANIZATION_NOT_VERIFIED)
            true)
        (let ((matching-amount (calculate-matching-amount campaign-id donation-amount))
              (total-needed (+ donation-amount matching-amount)))
            (try! (stx-transfer? donation-amount tx-sender (as-contract tx-sender)))
            (var-set total-donations (+ (var-get total-donations) donation-amount))
            (map-set donations tx-sender {
                total-donated: (+ (get-donation-total tx-sender) donation-amount),
                donation-count: (+ (get-donation-count tx-sender) u1),
                first-donation-block: (match (map-get? donations tx-sender)
                    existing-donation (get first-donation-block existing-donation)
                    stacks-block-height)
            })
            (map-set matching-campaigns campaign-id
                (merge campaign {
                    current-matched-amount: (+ (get current-matched-amount campaign) matching-amount),
                    total-donations-received: (+ (get total-donations-received campaign) donation-amount)
                }))
            (var-set total-matched-funds (+ (var-get total-matched-funds) matching-amount))
            (begin
                (unwrap-panic (process-donation-rewards tx-sender (+ donation-amount matching-amount)))
                (unwrap-panic (update-campaign-participant-stats tx-sender campaign-id matching-amount))
                (ok {donation-amount: donation-amount, matched-amount: matching-amount})))))

(define-public (end-campaign (campaign-id uint))
    (let ((campaign (unwrap! (map-get? matching-campaigns campaign-id) ERR_CAMPAIGN_NOT_FOUND))
          (unused-matching-funds (- (get max-matching-amount campaign) (get current-matched-amount campaign))))
        (asserts! (is-eq tx-sender (get sponsor campaign)) ERR_UNAUTHORIZED)
        (asserts! (get active campaign) ERR_CAMPAIGN_NOT_ACTIVE)
        (map-set matching-campaigns campaign-id
            (merge campaign {active: false}))
        (if (> unused-matching-funds u0)
            (try! (as-contract (stx-transfer? unused-matching-funds tx-sender (get sponsor campaign))))
            true)
        (ok unused-matching-funds)))

(define-public (emergency-end-campaign (campaign-id uint))
    (let ((campaign (unwrap! (map-get? matching-campaigns campaign-id) ERR_CAMPAIGN_NOT_FOUND))
          (unused-matching-funds (- (get max-matching-amount campaign) (get current-matched-amount campaign))))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (get active campaign) ERR_CAMPAIGN_NOT_ACTIVE)
        (map-set matching-campaigns campaign-id
            (merge campaign {active: false}))
        (if (> unused-matching-funds u0)
            (try! (as-contract (stx-transfer? unused-matching-funds tx-sender (get sponsor campaign))))
            true)
        (ok unused-matching-funds)))

(define-public (claim-achievement (achievement-id uint))
    (let ((achievement (unwrap! (map-get? achievement-definitions achievement-id) ERR_ORGANIZATION_NOT_FOUND))
          (donor-reward (get-donor-reward-data tx-sender)))
        (asserts! (get active achievement) ERR_ORGANIZATION_NOT_VERIFIED)
        (asserts! (not (is-achievement-claimed tx-sender achievement-id)) ERR_ORGANIZATION_ALREADY_VERIFIED)
        (asserts! (check-achievement-requirement tx-sender achievement-id) ERR_INSUFFICIENT_FUNDS)
        (let ((current-points (get total-points donor-reward))
              (reward-points (get points-reward achievement))
              (new-points (+ current-points reward-points))
              (current-achievements (get achievements donor-reward))
              (new-achievements (unwrap! (as-max-len? (append current-achievements achievement-id) u10) ERR_INVALID_AMOUNT)))
            (map-set donor-rewards tx-sender
                (merge donor-reward {
                    total-points: new-points,
                    achievements: new-achievements,
                    loyalty-tier: (calculate-loyalty-tier new-points)
                }))
            (var-set total-reward-points (+ (var-get total-reward-points) reward-points))
            (ok reward-points))))

(define-private (process-donation-rewards (donor principal) (amount uint))
    (let ((donor-reward (get-donor-reward-data donor))
          (base-points (/ amount (var-get reward-multiplier)))
          (streak-bonus (calculate-streak-bonus donor))
          (loyalty-bonus (calculate-loyalty-bonus donor))
          (total-points (+ base-points streak-bonus loyalty-bonus))
          (new-total-points (+ (get total-points donor-reward) total-points)))
        (map-set donor-rewards donor
            (merge donor-reward {
                total-points: new-total-points,
                last-donation-block: stacks-block-height,
                streak-days: (+ (get streak-days donor-reward) u1),
                loyalty-tier: (calculate-loyalty-tier new-total-points)
            }))
        (var-set total-reward-points (+ (var-get total-reward-points) total-points))
        (ok total-points)))

(define-private (process-referral-bonus (referrer principal))
    (let ((referrer-reward (get-donor-reward-data referrer))
          (bonus-points (/ (var-get loyalty-tier-threshold) (var-get reward-multiplier)))
          (new-total-points (+ (get total-points referrer-reward) bonus-points)))
        (map-set donor-rewards referrer
            (merge referrer-reward {
                total-points: new-total-points,
                referral-count: (+ (get referral-count referrer-reward) u1),
                loyalty-tier: (calculate-loyalty-tier new-total-points)
            }))
        (var-set total-reward-points (+ (var-get total-reward-points) bonus-points))
        (ok bonus-points)))

(define-private (calculate-streak-bonus (donor principal))
    (let ((donor-reward (get-donor-reward-data donor))
          (streak-days (get streak-days donor-reward))
          (last-donation-block (get last-donation-block donor-reward)))
        (if (and (> last-donation-block u0) (< (- stacks-block-height last-donation-block) u144))
            (/ (* streak-days u10) u100)
            u0)))

(define-private (calculate-loyalty-bonus (donor principal))
    (let ((donor-reward (get-donor-reward-data donor))
          (loyalty-tier (get loyalty-tier donor-reward)))
        (if (> loyalty-tier u0)
            (match (map-get? loyalty-tiers loyalty-tier)
                tier-data (/ (get bonus-percentage tier-data) u10)
                u0)
            u0)))

(define-private (calculate-loyalty-tier (points uint))
    (if (>= points (* (var-get loyalty-tier-threshold) u5))
        u5
        (if (>= points (* (var-get loyalty-tier-threshold) u4))
            u4
            (if (>= points (* (var-get loyalty-tier-threshold) u3))
                u3
                (if (>= points (* (var-get loyalty-tier-threshold) u2))
                    u2
                    (if (>= points (var-get loyalty-tier-threshold))
                        u1
                        u0))))))

(define-private (check-achievement-requirement (donor principal) (achievement-id uint))
    (let ((achievement (unwrap! (map-get? achievement-definitions achievement-id) false))
          (requirement-type (get requirement-type achievement))
          (requirement-value (get requirement-value achievement))
          (donor-data (map-get? donations donor)))
        (if (is-eq requirement-type "donation-count")
            (>= (get-donation-count donor) requirement-value)
            (if (is-eq requirement-type "total-donated")
                (>= (get-donation-total donor) requirement-value)
                (if (is-eq requirement-type "streak-days")
                    (>= (get streak-days (get-donor-reward-data donor)) requirement-value)
                    false)))))

(define-private (is-achievement-claimed (donor principal) (achievement-id uint))
    (let ((donor-reward (get-donor-reward-data donor))
          (achievements (get achievements donor-reward)))
        (is-some (index-of achievements achievement-id))))

(define-private (calculate-matching-amount (campaign-id uint) (donation-amount uint))
    (let ((campaign (unwrap! (map-get? matching-campaigns campaign-id) u0)))
        (if (get active campaign)
            (let ((potential-match (/ (* donation-amount (get matching-ratio-numerator campaign)) 
                                     (get matching-ratio-denominator campaign)))
                  (remaining-funds (- (get max-matching-amount campaign) 
                                    (get current-matched-amount campaign))))
                (if (> potential-match remaining-funds)
                    remaining-funds
                    potential-match))
            u0)))

(define-private (update-campaign-participant-stats (participant principal) (campaign-id uint) (matched-amount uint))
    (let ((current-stats (get-campaign-participant-stats participant)))
        (map-set campaign-participant-stats participant {
            total-campaigns-donated: (+ (get total-campaigns-donated current-stats) u1),
            total-matched-received: (+ (get total-matched-received current-stats) matched-amount),
            favorite-campaign-type: "general"
        })
        (ok true)))

(define-private (get-campaign-participant-stats (participant principal))
    (match (map-get? campaign-participant-stats participant)
        existing-stats existing-stats
        {
            total-campaigns-donated: u0,
            total-matched-received: u0,
            favorite-campaign-type: "general"
        }))

(define-private (is-campaign-active (campaign-id uint))
    (match (map-get? matching-campaigns campaign-id)
        campaign (and (get active campaign)
                     (>= stacks-block-height (get start-block campaign))
                     (< stacks-block-height (get end-block campaign)))
        false))

(define-private (get-donor-reward-data (donor principal))
    (match (map-get? donor-rewards donor)
        existing-reward existing-reward
        {
            total-points: u0,
            loyalty-tier: u0,
            streak-days: u0,
            last-donation-block: u0,
            achievements: (list),
            referral-count: u0,
            bonus-multiplier: u100
        }))

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

(define-read-only (get-donor-rewards (donor principal))
    (map-get? donor-rewards donor))

(define-read-only (get-donor-points (donor principal))
    (get total-points (get-donor-reward-data donor)))

(define-read-only (get-donor-loyalty-tier (donor principal))
    (get loyalty-tier (get-donor-reward-data donor)))

(define-read-only (get-donor-achievements (donor principal))
    (get achievements (get-donor-reward-data donor)))

(define-read-only (get-donor-referral-count (donor principal))
    (get referral-count (get-donor-reward-data donor)))

(define-read-only (get-achievement-info (achievement-id uint))
    (map-get? achievement-definitions achievement-id))

(define-read-only (get-loyalty-tier-info (tier-id uint))
    (map-get? loyalty-tiers tier-id))

(define-read-only (get-referral-info (donor principal))
    (map-get? donor-referrals donor))

(define-read-only (get-total-reward-points)
    (var-get total-reward-points))

(define-read-only (get-reward-system-stats)
    {
        total-reward-points: (var-get total-reward-points),
        loyalty-tier-threshold: (var-get loyalty-tier-threshold),
        reward-multiplier: (var-get reward-multiplier),
        achievement-counter: (var-get achievement-counter),
        referral-bonus-percentage: (var-get referral-bonus-percentage)
    })

(define-read-only (get-matching-campaign (campaign-id uint))
    (map-get? matching-campaigns campaign-id))

(define-read-only (get-campaign-donation-info (campaign-id uint) (donor principal))
    (map-get? campaign-donations campaign-id))

(define-read-only (get-campaign-participant-info (participant principal))
    (get-campaign-participant-stats participant))

(define-read-only (calculate-potential-match (campaign-id uint) (donation-amount uint))
    (calculate-matching-amount campaign-id donation-amount))

(define-read-only (is-campaign-currently-active (campaign-id uint))
    (is-campaign-active campaign-id))

(define-read-only (get-campaign-stats (campaign-id uint))
    (match (map-get? matching-campaigns campaign-id)
        campaign (some {
            total-donations: (get total-donations-received campaign),
            total-matched: (get current-matched-amount campaign),
            remaining-match-funds: (- (get max-matching-amount campaign) 
                                    (get current-matched-amount campaign)),
            match-ratio: {numerator: (get matching-ratio-numerator campaign), 
                         denominator: (get matching-ratio-denominator campaign)},
            active: (and (get active campaign)
                        (>= stacks-block-height (get start-block campaign))
                        (< stacks-block-height (get end-block campaign))),
            blocks-remaining: (if (>= stacks-block-height (get end-block campaign))
                                u0
                                (- (get end-block campaign) stacks-block-height))
        })
        none))

(define-read-only (get-total-matched-funds)
    (var-get total-matched-funds))

(define-read-only (get-matching-campaigns-count)
    (var-get matching-campaign-counter))

(define-read-only (get-contract-stats)
    {
        total-donations: (var-get total-donations),
        total-withdrawals: (var-get total-withdrawals),
        current-balance: (get-contract-balance),
        available-funds: (get-available-funds),
        emergency-fund: (get-emergency-fund),
        emergency-fund-percentage: (var-get emergency-fund-percentage),
        contract-paused: (var-get contract-paused),
        emergency-releases-count: (var-get emergency-release-counter),
        total-matched-funds: (var-get total-matched-funds),
        active-campaigns-count: (var-get matching-campaign-counter)
    })



