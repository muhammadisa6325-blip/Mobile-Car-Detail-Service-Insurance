;; title: detailing-service-oracle
;; version: 1.0.0
;; summary: Car detailing service quality monitoring and completion tracking oracle
;; description: Manages service provider registration, appointment scheduling, and quality tracking for mobile car detailing insurance

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_SERVICE_NOT_FOUND (err u101))
(define-constant ERR_PROVIDER_NOT_FOUND (err u102))
(define-constant ERR_INVALID_STATUS (err u103))
(define-constant ERR_SERVICE_ALREADY_EXISTS (err u104))
(define-constant ERR_PROVIDER_ALREADY_REGISTERED (err u105))
(define-constant ERR_INVALID_RATING (err u106))
(define-constant ERR_SERVICE_NOT_COMPLETED (err u107))
(define-constant ERR_ALREADY_RATED (err u108))

;; Service status enumeration
(define-constant STATUS_SCHEDULED u1)
(define-constant STATUS_IN_PROGRESS u2)
(define-constant STATUS_COMPLETED u3)
(define-constant STATUS_CANCELLED u4)
(define-constant STATUS_DISPUTED u5)

;; Data maps and variables
(define-map service-providers principal {
  name: (string-ascii 64),
  contact: (string-ascii 128),
  license-number: (string-ascii 32),
  registration-date: uint,
  is-active: bool,
  total-services: uint,
  average-rating: uint,
  total-ratings: uint,
  reputation-score: uint
})

(define-map service-appointments uint {
  customer: principal,
  provider: principal,
  vehicle-id: (string-ascii 64),
  service-type: (string-ascii 128),
  scheduled-date: uint,
  completion-date: (optional uint),
  status: uint,
  service-location: (string-ascii 256),
  estimated-duration: uint,
  actual-duration: (optional uint),
  service-cost: uint,
  special-instructions: (string-ascii 512)
})

(define-map service-quality-ratings uint {
  service-id: uint,
  customer: principal,
  overall-rating: uint,
  timeliness-rating: uint,
  quality-rating: uint,
  communication-rating: uint,
  cleanliness-rating: uint,
  feedback: (string-ascii 512),
  rating-date: uint
})

(define-map service-completion-proofs uint {
  service-id: uint,
  provider: principal,
  completion-timestamp: uint,
  before-photos-hash: (string-ascii 64),
  after-photos-hash: (string-ascii 64),
  work-performed: (string-ascii 512),
  materials-used: (string-ascii 256),
  completion-notes: (string-ascii 512)
})

(define-map provider-certifications principal {
  certification-type: (string-ascii 64),
  issuing-authority: (string-ascii 128),
  issue-date: uint,
  expiry-date: uint,
  certification-number: (string-ascii 64),
  is-valid: bool
})

(define-data-var next-service-id uint u1)
(define-data-var total-providers uint u0)
(define-data-var total-services uint u0)
(define-data-var contract-active bool true)

;; Private functions
(define-private (is-valid-status (status uint))
  (or (is-eq status STATUS_SCHEDULED)
      (or (is-eq status STATUS_IN_PROGRESS)
          (or (is-eq status STATUS_COMPLETED)
              (or (is-eq status STATUS_CANCELLED)
                  (is-eq status STATUS_DISPUTED))))))

(define-private (is-valid-rating (rating uint))
  (and (>= rating u1) (<= rating u5)))

(define-private (calculate-reputation-score (total-ratings uint) (average-rating uint) (total-services uint))
  (let ((base-score (* average-rating u20))
        (volume-bonus (if (>= total-services u50) u10 (/ total-services u5)))
        (rating-count-bonus (if (>= total-ratings u20) u5 (/ total-ratings u4))))
    (+ base-score (+ volume-bonus rating-count-bonus))))

(define-private (update-provider-statistics (provider principal) (rating uint))
  (let ((current-data (unwrap-panic (map-get? service-providers provider))))
    (let ((new-total-ratings (+ (get total-ratings current-data) u1))
          (new-total-services (+ (get total-services current-data) u1))
          (current-total-score (* (get average-rating current-data) (get total-ratings current-data)))
          (new-total-score (+ current-total-score rating))
          (new-average-rating (/ new-total-score new-total-ratings)))
      (let ((new-reputation (calculate-reputation-score new-total-ratings new-average-rating new-total-services)))
        (map-set service-providers provider
          (merge current-data {
            total-services: new-total-services,
            average-rating: new-average-rating,
            total-ratings: new-total-ratings,
            reputation-score: new-reputation
          }))))))

;; Public functions
(define-public (register-service-provider (name (string-ascii 64)) (contact (string-ascii 128)) (license-number (string-ascii 32)))
  (let ((provider tx-sender))
    (if (is-some (map-get? service-providers provider))
      ERR_PROVIDER_ALREADY_REGISTERED
      (begin
        (map-set service-providers provider {
          name: name,
          contact: contact,
          license-number: license-number,
          registration-date: block-height,
          is-active: true,
          total-services: u0,
          average-rating: u5,
          total-ratings: u0,
          reputation-score: u100
        })
        (var-set total-providers (+ (var-get total-providers) u1))
        (ok provider)))))

(define-public (schedule-service (provider principal) (vehicle-id (string-ascii 64)) (service-type (string-ascii 128))
                                (service-location (string-ascii 256)) (estimated-duration uint) (service-cost uint)
                                (special-instructions (string-ascii 512)))
  (let ((service-id (var-get next-service-id))
        (customer tx-sender))
    (if (is-none (map-get? service-providers provider))
      ERR_PROVIDER_NOT_FOUND
      (begin
        (map-set service-appointments service-id {
          customer: customer,
          provider: provider,
          vehicle-id: vehicle-id,
          service-type: service-type,
          scheduled-date: block-height,
          completion-date: none,
          status: STATUS_SCHEDULED,
          service-location: service-location,
          estimated-duration: estimated-duration,
          actual-duration: none,
          service-cost: service-cost,
          special-instructions: special-instructions
        })
        (var-set next-service-id (+ service-id u1))
        (var-set total-services (+ (var-get total-services) u1))
        (ok service-id)))))

(define-public (update-service-status (service-id uint) (new-status uint))
  (let ((service-data (unwrap! (map-get? service-appointments service-id) ERR_SERVICE_NOT_FOUND)))
    (if (not (is-valid-status new-status))
      ERR_INVALID_STATUS
      (if (not (is-eq tx-sender (get provider service-data)))
        ERR_UNAUTHORIZED
        (begin
          (map-set service-appointments service-id
            (merge service-data { status: new-status }))
          (ok new-status))))))

(define-public (complete-service (service-id uint) (actual-duration uint) (before-photos-hash (string-ascii 64))
                                (after-photos-hash (string-ascii 64)) (work-performed (string-ascii 512))
                                (materials-used (string-ascii 256)) (completion-notes (string-ascii 512)))
  (let ((service-data (unwrap! (map-get? service-appointments service-id) ERR_SERVICE_NOT_FOUND)))
    (if (not (is-eq tx-sender (get provider service-data)))
      ERR_UNAUTHORIZED
      (begin
        (map-set service-appointments service-id
          (merge service-data {
            completion-date: (some block-height),
            status: STATUS_COMPLETED,
            actual-duration: (some actual-duration)
          }))
        (map-set service-completion-proofs service-id {
          service-id: service-id,
          provider: (get provider service-data),
          completion-timestamp: block-height,
          before-photos-hash: before-photos-hash,
          after-photos-hash: after-photos-hash,
          work-performed: work-performed,
          materials-used: materials-used,
          completion-notes: completion-notes
        })
        (ok service-id)))))

(define-public (rate-service (service-id uint) (overall-rating uint) (timeliness-rating uint)
                            (quality-rating uint) (communication-rating uint) (cleanliness-rating uint)
                            (feedback (string-ascii 512)))
  (let ((service-data (unwrap! (map-get? service-appointments service-id) ERR_SERVICE_NOT_FOUND)))
    (if (not (is-eq tx-sender (get customer service-data)))
      ERR_UNAUTHORIZED
      (if (not (is-eq (get status service-data) STATUS_COMPLETED))
        ERR_SERVICE_NOT_COMPLETED
        (if (is-some (map-get? service-quality-ratings service-id))
          ERR_ALREADY_RATED
          (if (not (and (is-valid-rating overall-rating)
                       (and (is-valid-rating timeliness-rating)
                            (and (is-valid-rating quality-rating)
                                 (and (is-valid-rating communication-rating)
                                      (is-valid-rating cleanliness-rating))))))
            ERR_INVALID_RATING
            (begin
              (map-set service-quality-ratings service-id {
                service-id: service-id,
                customer: tx-sender,
                overall-rating: overall-rating,
                timeliness-rating: timeliness-rating,
                quality-rating: quality-rating,
                communication-rating: communication-rating,
                cleanliness-rating: cleanliness-rating,
                feedback: feedback,
                rating-date: block-height
              })
              (update-provider-statistics (get provider service-data) overall-rating)
              (ok service-id))))))))

(define-public (add-provider-certification (certification-type (string-ascii 64)) (issuing-authority (string-ascii 128))
                                          (issue-date uint) (expiry-date uint) (certification-number (string-ascii 64)))
  (begin
    (map-set provider-certifications tx-sender {
      certification-type: certification-type,
      issuing-authority: issuing-authority,
      issue-date: issue-date,
      expiry-date: expiry-date,
      certification-number: certification-number,
      is-valid: (> expiry-date block-height)
    })
    (ok tx-sender)))

;; Read-only functions
(define-read-only (get-service-provider (provider principal))
  (map-get? service-providers provider))

(define-read-only (get-service-appointment (service-id uint))
  (map-get? service-appointments service-id))

(define-read-only (get-service-rating (service-id uint))
  (map-get? service-quality-ratings service-id))

(define-read-only (get-service-proof (service-id uint))
  (map-get? service-completion-proofs service-id))

(define-read-only (get-provider-certification (provider principal))
  (map-get? provider-certifications provider))

(define-read-only (get-contract-info)
  {
    total-providers: (var-get total-providers),
    total-services: (var-get total-services),
    next-service-id: (var-get next-service-id),
    contract-active: (var-get contract-active)
  })
