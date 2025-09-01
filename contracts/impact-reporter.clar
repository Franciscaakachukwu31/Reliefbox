;; Disaster Impact Assessment & Transparency Reporter
;; Tracks disaster relief impact metrics and provides transparency reporting

(define-constant ERR-NOT-AUTHORIZED (err u600))
(define-constant ERR-DISASTER-NOT-FOUND (err u601))
(define-constant ERR-INVALID-METRICS (err u602))
(define-constant ERR-REPORT-ALREADY-EXISTS (err u603))
(define-constant ERR-ORGANIZATION-NOT-VERIFIED (err u604))
(define-constant ERR-INSUFFICIENT-DATA (err u605))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-EFFICIENCY-SCORE u40) ;; Minimum 40% efficiency for good rating
(define-constant TRANSPARENCY-THRESHOLD u70) ;; Transparency score threshold

;; Data tracking variables
(define-data-var next-disaster-id uint u1)
(define-data-var next-report-id uint u1)
(define-data-var total-disasters-tracked uint u0)

;; Disaster event registry with impact tracking
(define-map disaster-events
    uint ;; disaster-id
    {
        name: (string-ascii 100),
        disaster-type: (string-ascii 30),
        location: (string-ascii 100),
        severity-level: uint, ;; 1-10 scale
        people-affected: uint,
        estimated-damage: uint,
        relief-needed: uint,
        start-date: uint,
        reported-by: principal,
        verified: bool
    }
)

;; Organization impact reports per disaster
(define-map impact-reports
    {disaster-id: uint, organization: principal}
    {
        funds-allocated: uint,
        people-helped: uint,
        supplies-distributed: uint,
        efficiency-score: uint, ;; Calculated as (people-helped * 100) / funds-allocated
        transparency-score: uint, ;; Based on reporting completeness
        report-date: uint,
        verified-by: principal,
        impact-description: (string-ascii 300)
    }
)

;; Organization efficiency tracking across disasters
(define-map organization-efficiency
    principal
    {
        total-disasters-responded: uint,
        total-funds-managed: uint,
        total-people-helped: uint,
        average-efficiency-score: uint,
        average-transparency-score: uint,
        trust-rating: uint, ;; 1-5 stars based on performance
        last-updated: uint
    }
)

;; Disaster summary metrics
(define-map disaster-summaries
    uint ;; disaster-id
    {
        total-funds-allocated: uint,
        total-people-helped: uint,
        participating-organizations: uint,
        best-performing-org: (optional principal),
        overall-efficiency: uint,
        relief-completion-percentage: uint,
        last-updated: uint
    }
)

;; Transparency audit logs
(define-map transparency-logs
    uint ;; report-id
    {
        disaster-id: uint,
        organization: principal,
        audit-type: (string-ascii 50),
        findings: (string-ascii 400),
        auditor: principal,
        audit-date: uint,
        compliance-score: uint
    }
)

;; Register a new disaster event (verified organizations or owner)
(define-public (register-disaster-event 
    (name (string-ascii 100))
    (disaster-type (string-ascii 30))
    (location (string-ascii 100))
    (severity-level uint)
    (people-affected uint)
    (estimated-damage uint)
    (relief-needed uint))
    (let ((disaster-id (var-get next-disaster-id)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-organization-verified tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= severity-level u1) (<= severity-level u10)) ERR-INVALID-METRICS)
        (asserts! (> people-affected u0) ERR-INVALID-METRICS)
        
        (map-set disaster-events disaster-id
            {
                name: name,
                disaster-type: disaster-type,
                location: location,
                severity-level: severity-level,
                people-affected: people-affected,
                estimated-damage: estimated-damage,
                relief-needed: relief-needed,
                start-date: stacks-block-height,
                reported-by: tx-sender,
                verified: (is-eq tx-sender CONTRACT-OWNER)
            }
        )
        
        (var-set next-disaster-id (+ disaster-id u1))
        (var-set total-disasters-tracked (+ (var-get total-disasters-tracked) u1))
        (ok disaster-id)
    )
)

;; Submit impact report for organization's relief work
(define-public (submit-impact-report 
    (disaster-id uint)
    (funds-allocated uint)
    (people-helped uint)
    (supplies-distributed uint)
    (impact-description (string-ascii 300)))
    (let ((disaster (unwrap! (map-get? disaster-events disaster-id) ERR-DISASTER-NOT-FOUND))
          (efficiency-score (calculate-efficiency-score funds-allocated people-helped))
          (transparency-score (calculate-transparency-score impact-description supplies-distributed)))
        
        (asserts! (is-organization-verified tx-sender) ERR-ORGANIZATION-NOT-VERIFIED)
        (asserts! (> funds-allocated u0) ERR-INVALID-METRICS)
        (asserts! (is-none (map-get? impact-reports {disaster-id: disaster-id, organization: tx-sender})) ERR-REPORT-ALREADY-EXISTS)
        
        (map-set impact-reports {disaster-id: disaster-id, organization: tx-sender}
            {
                funds-allocated: funds-allocated,
                people-helped: people-helped,
                supplies-distributed: supplies-distributed,
                efficiency-score: efficiency-score,
                transparency-score: transparency-score,
                report-date: stacks-block-height,
                verified-by: tx-sender,
                impact-description: impact-description
            }
        )
        
        ;; Update organization efficiency metrics
        (update-organization-efficiency tx-sender funds-allocated people-helped efficiency-score transparency-score)
        
        ;; Update disaster summary
        (update-disaster-summary disaster-id funds-allocated people-helped)
        
        (ok {
            efficiency-score: efficiency-score,
            transparency-score: transparency-score
        })
    )
)

;; Verify disaster event (owner only)
(define-public (verify-disaster-event (disaster-id uint))
    (let ((disaster (unwrap! (map-get? disaster-events disaster-id) ERR-DISASTER-NOT-FOUND)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        
        (map-set disaster-events disaster-id
            (merge disaster {verified: true})
        )
        (ok true)
    )
)

;; Create transparency audit report
(define-public (create-transparency-audit 
    (disaster-id uint)
    (organization principal)
    (audit-type (string-ascii 50))
    (findings (string-ascii 400))
    (compliance-score uint))
    (let ((report-id (var-get next-report-id)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (<= compliance-score u100) ERR-INVALID-METRICS)
        (asserts! (is-some (map-get? disaster-events disaster-id)) ERR-DISASTER-NOT-FOUND)
        
        (map-set transparency-logs report-id
            {
                disaster-id: disaster-id,
                organization: organization,
                audit-type: audit-type,
                findings: findings,
                auditor: tx-sender,
                audit-date: stacks-block-height,
                compliance-score: compliance-score
            }
        )
        
        (var-set next-report-id (+ report-id u1))
        (ok report-id)
    )
)

;; Private helper functions
(define-private (calculate-efficiency-score (funds-allocated uint) (people-helped uint))
    (if (> funds-allocated u0)
        (let ((raw-score (/ (* people-helped u10000) funds-allocated)))
            (if (> raw-score u100)
                u100
                raw-score)
        )
        u0
    )
)

(define-private (calculate-transparency-score (description (string-ascii 300)) (supplies-distributed uint))
    (let ((desc-length (len description))
          (base-score (if (> supplies-distributed u0) u50 u20))
          (desc-bonus (if (>= desc-length u50) u30 (/ (* desc-length u30) u50))))
        (+ base-score desc-bonus)
    )
)

(define-private (update-organization-efficiency 
    (organization principal) 
    (funds-allocated uint) 
    (people-helped uint) 
    (efficiency-score uint) 
    (transparency-score uint))
    (let ((current-data (get-organization-efficiency-data organization))
          (new-total-disasters (+ (get total-disasters-responded current-data) u1))
          (new-total-funds (+ (get total-funds-managed current-data) funds-allocated))
          (new-total-people (+ (get total-people-helped current-data) people-helped))
          (new-avg-efficiency (/ (+ (* (get average-efficiency-score current-data) (get total-disasters-responded current-data)) efficiency-score) new-total-disasters))
          (new-avg-transparency (/ (+ (* (get average-transparency-score current-data) (get total-disasters-responded current-data)) transparency-score) new-total-disasters)))
        
        (map-set organization-efficiency organization
            {
                total-disasters-responded: new-total-disasters,
                total-funds-managed: new-total-funds,
                total-people-helped: new-total-people,
                average-efficiency-score: new-avg-efficiency,
                average-transparency-score: new-avg-transparency,
                trust-rating: (calculate-trust-rating new-avg-efficiency new-avg-transparency),
                last-updated: stacks-block-height
            }
        )
    )
)

(define-private (update-disaster-summary (disaster-id uint) (funds-allocated uint) (people-helped uint))
    (let ((current-summary (get-disaster-summary-data disaster-id))
          (new-total-funds (+ (get total-funds-allocated current-summary) funds-allocated))
          (new-total-people (+ (get total-people-helped current-summary) people-helped))
          (new-org-count (+ (get participating-organizations current-summary) u1)))
        
        (map-set disaster-summaries disaster-id
            {
                total-funds-allocated: new-total-funds,
                total-people-helped: new-total-people,
                participating-organizations: new-org-count,
                best-performing-org: (get best-performing-org current-summary),
                overall-efficiency: (/ (* new-total-people u100) new-total-funds),
                relief-completion-percentage: u0, ;; Would be calculated based on relief-needed
                last-updated: stacks-block-height
            }
        )
    )
)

(define-private (calculate-trust-rating (efficiency-score uint) (transparency-score uint))
    (let ((combined-score (/ (+ efficiency-score transparency-score) u2)))
        (if (>= combined-score u90)
            u5
            (if (>= combined-score u75)
                u4
                (if (>= combined-score u60)
                    u3
                    (if (>= combined-score u40)
                        u2
                        u1
                    )
                )
            )
        )
    )
)

(define-private (get-organization-efficiency-data (organization principal))
    (default-to
        {
            total-disasters-responded: u0,
            total-funds-managed: u0,
            total-people-helped: u0,
            average-efficiency-score: u0,
            average-transparency-score: u0,
            trust-rating: u0,
            last-updated: u0
        }
        (map-get? organization-efficiency organization)
    )
)

(define-private (get-disaster-summary-data (disaster-id uint))
    (default-to
        {
            total-funds-allocated: u0,
            total-people-helped: u0,
            participating-organizations: u0,
            best-performing-org: none,
            overall-efficiency: u0,
            relief-completion-percentage: u0,
            last-updated: u0
        }
        (map-get? disaster-summaries disaster-id)
    )
)

(define-private (is-organization-verified (organization principal))
    ;; This would integrate with the main Reliefbox contract
    ;; For now, simplified check
    (not (is-eq organization CONTRACT-OWNER))
)

;; Read-only functions
(define-read-only (get-disaster-event (disaster-id uint))
    (map-get? disaster-events disaster-id)
)

(define-read-only (get-impact-report (disaster-id uint) (organization principal))
    (map-get? impact-reports {disaster-id: disaster-id, organization: organization})
)

(define-read-only (get-organization-efficiency (organization principal))
    (map-get? organization-efficiency organization)
)

(define-read-only (get-disaster-summary (disaster-id uint))
    (map-get? disaster-summaries disaster-id)
)

(define-read-only (get-transparency-audit (report-id uint))
    (map-get? transparency-logs report-id)
)

(define-read-only (get-impact-statistics)
    {
        total-disasters: (var-get total-disasters-tracked),
        next-disaster-id: (var-get next-disaster-id),
        next-report-id: (var-get next-report-id)
    }
)

(define-read-only (calculate-organization-ranking (organization principal))
    (let ((efficiency-data (get-organization-efficiency-data organization)))
        (ok {
            efficiency-score: (get average-efficiency-score efficiency-data),
            transparency-score: (get average-transparency-score efficiency-data),
            trust-rating: (get trust-rating efficiency-data),
            total-impact: (get total-people-helped efficiency-data),
            disasters-responded: (get total-disasters-responded efficiency-data)
        })
    )
)

(define-read-only (get-disaster-efficiency-ranking (disaster-id uint))
    (match (map-get? disaster-summaries disaster-id)
        summary (ok {
            overall-efficiency: (get overall-efficiency summary),
            total-organizations: (get participating-organizations summary),
            people-helped: (get total-people-helped summary),
            funds-allocated: (get total-funds-allocated summary)
        })
        (err ERR-DISASTER-NOT-FOUND)
    )
)
