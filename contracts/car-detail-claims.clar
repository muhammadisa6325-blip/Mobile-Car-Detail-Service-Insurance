;; title: car-detail-claims
;; version: 1.0.0
;; summary: Automated compensation for vehicle damage and service quality issues
;; description: Comprehensive claims processing system for mobile car detailing insurance with automated payouts and dispute resolution

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_CLAIM_NOT_FOUND (err u301))
(define-constant ERR_CLAIM_ALREADY_EXISTS (err u302))
(define-constant ERR_INVALID_CLAIM_TYPE (err u303))
(define-constant ERR_INSUFFICIENT_FUNDS (err u304))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u305))
(define-constant ERR_INVALID_AMOUNT (err u306))
(define-constant ERR_POLICY_NOT_FOUND (err u307))
(define-constant ERR_POLICY_EXPIRED (err u308))
(define-constant ERR_CLAIM_DENIED (err u309))
(define-constant ERR_INVALID_EVIDENCE (err u310))
(define-constant ERR_DISPUTE_NOT_FOUND (err u311))
(define-constant ERR_ARBITRATION_IN_PROGRESS (err u312))

;; Claim types
(define-constant CLAIM_VEHICLE_DAMAGE u1)
(define-constant CLAIM_CHEMICAL_SPILL u2)
(define-constant CLAIM_SERVICE_QUALITY u3)
(define-constant CLAIM_EQUIPMENT_DAMAGE u4)
(define-constant CLAIM_THEFT_VANDALISM u5)

;; Claim status
(define-constant STATUS_SUBMITTED u1)
(define-constant STATUS_UNDER_REVIEW u2)
(define-constant STATUS_APPROVED u3)
(define-constant STATUS_DENIED u4)
(define-constant STATUS_PAID u5)
(define-constant STATUS_DISPUTED u6)
(define-constant STATUS_ARBITRATION u7)

;; Policy types
(define-constant POLICY_BASIC u1)
(define-constant POLICY_COMPREHENSIVE u2)
(define-constant POLICY_PREMIUM u3)

;; Data maps and variables
(define-map insurance-policies principal {
  policy-type: uint,
  premium-amount: uint,
  coverage-limit: uint,
  deductible: uint,
  start-date: uint,
  expiry-date: uint,
  is-active: bool,
  total-claims: uint,
  total-payouts: uint,
  risk-score: uint
})

(define-map claims-registry uint {
  claimant: principal,
  provider: principal,
  claim-type: uint,
  service-id: uint,
  vehicle-id: (string-ascii 64),
  claim-amount: uint,
  description: (string-ascii 1024),
  submission-date: uint,
  status: uint,
  evidence-hashes: (list 10 (string-ascii 64)),
  adjuster: (optional principal),
  review-date: (optional uint),
  approval-date: (optional uint),
  payment-date: (optional uint),
  denial-reason: (optional (string-ascii 512)),
  final-payout: (optional uint)
})

(define-map claim-assessments uint {
  claim-id: uint,
  assessor: principal,
  assessment-date: uint,
  damage-verified: bool,
  estimated-cost: uint,
  recommended-action: (string-ascii 256),
  assessment-notes: (string-ascii 1024),
  supporting-evidence: (list 5 (string-ascii 64)),
  risk-factors: (string-ascii 512)
})

(define-map premium-calculations principal {
  base-premium: uint,
  risk-multiplier: uint,
  discount-factors: uint,
  final-premium: uint,
  calculation-date: uint,
  next-review-date: uint
})

(define-map dispute-records uint {
  claim-id: uint,
  disputer: principal,
  dispute-reason: (string-ascii 512),
  submission-date: uint,
  arbitrator: (optional principal),
  arbitration-date: (optional uint),
  resolution: (optional (string-ascii 1024)),
  final-decision: (optional bool),
  resolution-date: (optional uint)
})

(define-map payout-records uint {
  claim-id: uint,
  recipient: principal,
  amount: uint,
  payment-method: (string-ascii 32),
  transaction-hash: (string-ascii 64),
  payment-date: uint,
  processing-fee: uint,
  net-amount: uint
})

(define-map fraud-indicators uint {
  claim-id: uint,
  indicator-type: (string-ascii 64),
  severity-level: uint,
  description: (string-ascii 512),
  detection-date: uint,
  flagged-by: principal,
  investigation-required: bool
})

(define-data-var next-claim-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var total-policies uint u0)
(define-data-var total-claims uint u0)
(define-data-var total-payouts uint u0)
(define-data-var contract-balance uint u0)
(define-data-var claim-processing-fee uint u25)
(define-data-var max-claim-amount uint u100000)
(define-data-var auto-approve-threshold uint u1000)

;; Private functions
(define-private (is-valid-claim-type (claim-type uint))
  (and (>= claim-type CLAIM_VEHICLE_DAMAGE) (<= claim-type CLAIM_THEFT_VANDALISM)))

(define-private (is-valid-policy-type (policy-type uint))
  (and (>= policy-type POLICY_BASIC) (<= policy-type POLICY_PREMIUM)))

(define-private (calculate-coverage-limit (policy-type uint))
  (if (is-eq policy-type POLICY_BASIC)
    u10000
    (if (is-eq policy-type POLICY_COMPREHENSIVE)
      u50000
      u100000)))

(define-private (calculate-deductible (policy-type uint) (claim-amount uint))
  (let ((deductible-rate (if (is-eq policy-type POLICY_BASIC) u10
                            (if (is-eq policy-type POLICY_COMPREHENSIVE) u5 u2))))
    (/ (* claim-amount deductible-rate) u100)))

(define-private (calculate-premium (policy-type uint) (risk-score uint))
  (let ((base-premium (if (is-eq policy-type POLICY_BASIC) u500
                         (if (is-eq policy-type POLICY_COMPREHENSIVE) u1200 u2000)))
        (risk-multiplier (/ (+ risk-score u50) u100)))
    (* base-premium risk-multiplier)))

(define-private (is-policy-active (claimant principal))
  (match (map-get? insurance-policies claimant)
    policy (and (get is-active policy) (> (get expiry-date policy) block-height))
    false))

(define-private (calculate-final-payout (claim-amount uint) (policy-type uint) (damage-verified bool))
  (if damage-verified
    (let ((coverage-limit (calculate-coverage-limit policy-type))
          (deductible (calculate-deductible policy-type claim-amount))
          (covered-amount (if (> claim-amount coverage-limit) coverage-limit claim-amount)))
      (if (> covered-amount deductible)
        (- covered-amount deductible)
        u0))
    u0))

(define-private (detect-fraud-indicators (claim-id uint) (claim-amount uint) (claimant principal))
  (let ((policy-data (unwrap-panic (map-get? insurance-policies claimant))))
    (let ((high-amount-flag (> claim-amount (/ (* (get coverage-limit policy-data) u8) u10)))
          (frequent-claims-flag (> (get total-claims policy-data) u5))
          (recent-policy-flag (< (- block-height (get start-date policy-data)) u1000)))
      (if (or high-amount-flag (or frequent-claims-flag recent-policy-flag))
        (begin
          (map-set fraud-indicators claim-id {
            claim-id: claim-id,
            indicator-type: "suspicious-pattern",
            severity-level: (if high-amount-flag u3 u1),
            description: "Automated fraud detection triggered",
            detection-date: block-height,
            flagged-by: CONTRACT_OWNER,
            investigation-required: true
          })
          true)
        true))))

(define-private (update-policy-statistics (claimant principal) (payout-amount uint))
  (let ((policy-data (unwrap-panic (map-get? insurance-policies claimant))))
    (map-set insurance-policies claimant
      (merge policy-data {
        total-claims: (+ (get total-claims policy-data) u1),
        total-payouts: (+ (get total-payouts policy-data) payout-amount),
        risk-score: (min u200 (+ (get risk-score policy-data) u10))
      }))))

;; Public functions
(define-public (purchase-policy (policy-type uint))
  (let ((customer tx-sender))
    (if (not (is-valid-policy-type policy-type))
      ERR_INVALID_CLAIM_TYPE
      (if (is-some (map-get? insurance-policies customer))
        ERR_CLAIM_ALREADY_EXISTS
        (let ((premium (calculate-premium policy-type u100))
              (coverage-limit (calculate-coverage-limit policy-type))
              (deductible (calculate-deductible policy-type u1000)))
          (map-set insurance-policies customer {
            policy-type: policy-type,
            premium-amount: premium,
            coverage-limit: coverage-limit,
            deductible: deductible,
            start-date: block-height,
            expiry-date: (+ block-height u52560), ;; Approximately 1 year
            is-active: true,
            total-claims: u0,
            total-payouts: u0,
            risk-score: u100
          })
          (var-set total-policies (+ (var-get total-policies) u1))
          (ok customer))))))

(define-public (submit-claim (provider principal) (claim-type uint) (service-id uint) (vehicle-id (string-ascii 64))
                            (claim-amount uint) (description (string-ascii 1024)) (evidence-hashes (list 10 (string-ascii 64))))
  (let ((claim-id (var-get next-claim-id))
        (claimant tx-sender))
    (if (not (is-valid-claim-type claim-type))
      ERR_INVALID_CLAIM_TYPE
      (if (not (is-policy-active claimant))
        ERR_POLICY_EXPIRED
        (if (> claim-amount (var-get max-claim-amount))
          ERR_INVALID_AMOUNT
          (begin
            (map-set claims-registry claim-id {
              claimant: claimant,
              provider: provider,
              claim-type: claim-type,
              service-id: service-id,
              vehicle-id: vehicle-id,
              claim-amount: claim-amount,
              description: description,
              submission-date: block-height,
              status: STATUS_SUBMITTED,
              evidence-hashes: evidence-hashes,
              adjuster: none,
              review-date: none,
              approval-date: none,
              payment-date: none,
              denial-reason: none,
              final-payout: none
            })
            (detect-fraud-indicators claim-id claim-amount claimant)
            (var-set next-claim-id (+ claim-id u1))
            (var-set total-claims (+ (var-get total-claims) u1))
            (ok claim-id)))))))

(define-public (assess-claim (claim-id uint) (damage-verified bool) (estimated-cost uint) 
                            (recommended-action (string-ascii 256)) (assessment-notes (string-ascii 1024))
                            (supporting-evidence (list 5 (string-ascii 64))) (risk-factors (string-ascii 512)))
  (let ((claim-data (unwrap! (map-get? claims-registry claim-id) ERR_CLAIM_NOT_FOUND)))
    (if (not (is-eq (get status claim-data) STATUS_SUBMITTED))
      ERR_CLAIM_ALREADY_PROCESSED
      (begin
        (map-set claim-assessments claim-id {
          claim-id: claim-id,
          assessor: tx-sender,
          assessment-date: block-height,
          damage-verified: damage-verified,
          estimated-cost: estimated-cost,
          recommended-action: recommended-action,
          assessment-notes: assessment-notes,
          supporting-evidence: supporting-evidence,
          risk-factors: risk-factors
        })
        (map-set claims-registry claim-id
          (merge claim-data {
            status: STATUS_UNDER_REVIEW,
            adjuster: (some tx-sender),
            review-date: (some block-height)
          }))
        (ok claim-id)))))

(define-public (approve-claim (claim-id uint))
  (let ((claim-data (unwrap! (map-get? claims-registry claim-id) ERR_CLAIM_NOT_FOUND))
        (assessment (unwrap! (map-get? claim-assessments claim-id) ERR_CLAIM_NOT_FOUND)))
    (if (not (is-eq (get status claim-data) STATUS_UNDER_REVIEW))
      ERR_CLAIM_ALREADY_PROCESSED
      (if (not (is-eq tx-sender CONTRACT_OWNER))
        ERR_UNAUTHORIZED
        (let ((policy-data (unwrap! (map-get? insurance-policies (get claimant claim-data)) ERR_POLICY_NOT_FOUND))
              (final-payout (calculate-final-payout (get claim-amount claim-data) (get policy-type policy-data) (get damage-verified assessment))))
          (if (> final-payout u0)
            (begin
              (map-set claims-registry claim-id
                (merge claim-data {
                  status: STATUS_APPROVED,
                  approval-date: (some block-height),
                  final-payout: (some final-payout)
                }))
              (ok final-payout))
            ERR_CLAIM_DENIED))))))

(define-public (process-payout (claim-id uint) (payment-method (string-ascii 32)) (transaction-hash (string-ascii 64)))
  (let ((claim-data (unwrap! (map-get? claims-registry claim-id) ERR_CLAIM_NOT_FOUND)))
    (if (not (is-eq (get status claim-data) STATUS_APPROVED))
      ERR_CLAIM_ALREADY_PROCESSED
      (if (not (is-eq tx-sender CONTRACT_OWNER))
        ERR_UNAUTHORIZED
        (let ((payout-amount (unwrap-panic (get final-payout claim-data)))
              (processing-fee (var-get claim-processing-fee))
              (net-amount (- payout-amount processing-fee)))
          (if (> payout-amount (var-get contract-balance))
            ERR_INSUFFICIENT_FUNDS
            (begin
              (map-set payout-records claim-id {
                claim-id: claim-id,
                recipient: (get claimant claim-data),
                amount: payout-amount,
                payment-method: payment-method,
                transaction-hash: transaction-hash,
                payment-date: block-height,
                processing-fee: processing-fee,
                net-amount: net-amount
              })
              (map-set claims-registry claim-id
                (merge claim-data {
                  status: STATUS_PAID,
                  payment-date: (some block-height)
                }))
              (update-policy-statistics (get claimant claim-data) payout-amount)
              (var-set contract-balance (- (var-get contract-balance) payout-amount))
              (var-set total-payouts (+ (var-get total-payouts) payout-amount))
              (ok net-amount))))))))

(define-public (dispute-claim (claim-id uint) (dispute-reason (string-ascii 512)))
  (let ((claim-data (unwrap! (map-get? claims-registry claim-id) ERR_CLAIM_NOT_FOUND))
        (dispute-id (var-get next-dispute-id)))
    (if (not (is-eq tx-sender (get claimant claim-data)))
      ERR_UNAUTHORIZED
      (if (is-eq (get status claim-data) STATUS_PAID)
        ERR_CLAIM_ALREADY_PROCESSED
        (begin
          (map-set dispute-records dispute-id {
            claim-id: claim-id,
            disputer: tx-sender,
            dispute-reason: dispute-reason,
            submission-date: block-height,
            arbitrator: none,
            arbitration-date: none,
            resolution: none,
            final-decision: none,
            resolution-date: none
          })
          (map-set claims-registry claim-id
            (merge claim-data { status: STATUS_DISPUTED }))
          (var-set next-dispute-id (+ dispute-id u1))
          (ok dispute-id))))))

(define-public (resolve-dispute (dispute-id uint) (final-decision bool) (resolution (string-ascii 1024)))
  (let ((dispute-data (unwrap! (map-get? dispute-records dispute-id) ERR_DISPUTE_NOT_FOUND)))
    (if (not (is-eq tx-sender CONTRACT_OWNER))
      ERR_UNAUTHORIZED
      (let ((claim-data (unwrap-panic (map-get? claims-registry (get claim-id dispute-data)))))
        (map-set dispute-records dispute-id
          (merge dispute-data {
            arbitrator: (some tx-sender),
            arbitration-date: (some block-height),
            resolution: (some resolution),
            final-decision: (some final-decision),
            resolution-date: (some block-height)
          }))
        (map-set claims-registry (get claim-id dispute-data)
          (merge claim-data {
            status: (if final-decision STATUS_APPROVED STATUS_DENIED)
          }))
        (ok final-decision)))))

(define-public (fund-contract (amount uint))
  (if (> amount u0)
    (begin
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (var-set contract-balance (+ (var-get contract-balance) amount))
      (ok amount))
    ERR_INVALID_AMOUNT))

;; Read-only functions
(define-read-only (get-policy (customer principal))
  (map-get? insurance-policies customer))

(define-read-only (get-claim (claim-id uint))
  (map-get? claims-registry claim-id))

(define-read-only (get-claim-assessment (claim-id uint))
  (map-get? claim-assessments claim-id))

(define-read-only (get-payout-record (claim-id uint))
  (map-get? payout-records claim-id))

(define-read-only (get-dispute-record (dispute-id uint))
  (map-get? dispute-records dispute-id))

(define-read-only (get-fraud-indicators (claim-id uint))
  (map-get? fraud-indicators claim-id))

(define-read-only (get-contract-statistics)
  {
    total-policies: (var-get total-policies),
    total-claims: (var-get total-claims),
    total-payouts: (var-get total-payouts),
    contract-balance: (var-get contract-balance),
    next-claim-id: (var-get next-claim-id),
    processing-fee: (var-get claim-processing-fee)
  })

(define-read-only (calculate-premium-quote (policy-type uint) (risk-score uint))
  (if (is-valid-policy-type policy-type)
    (some (calculate-premium policy-type risk-score))
    none))
