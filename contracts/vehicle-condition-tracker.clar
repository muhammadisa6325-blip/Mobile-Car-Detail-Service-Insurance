;; title: vehicle-condition-tracker
;; version: 1.0.0
;; summary: Customer vehicle condition assessment before and after detailing service
;; description: Comprehensive tracking system for vehicle condition documentation and damage assessment

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_VEHICLE_NOT_FOUND (err u201))
(define-constant ERR_ASSESSMENT_NOT_FOUND (err u202))
(define-constant ERR_ASSESSMENT_EXISTS (err u203))
(define-constant ERR_INVALID_CONDITION_SCORE (err u204))
(define-constant ERR_INVALID_DAMAGE_LEVEL (err u205))
(define-constant ERR_POST_ASSESSMENT_EXISTS (err u206))
(define-constant ERR_PRE_ASSESSMENT_MISSING (err u207))
(define-constant ERR_INVALID_MILEAGE (err u208))
(define-constant ERR_INVALID_SERVICE_ID (err u209))

;; Condition score ranges (1-10 scale)
(define-constant MIN_CONDITION_SCORE u1)
(define-constant MAX_CONDITION_SCORE u10)

;; Damage level enumeration
(define-constant DAMAGE_NONE u0)
(define-constant DAMAGE_MINOR u1)
(define-constant DAMAGE_MODERATE u2)
(define-constant DAMAGE_MAJOR u3)
(define-constant DAMAGE_SEVERE u4)

;; Assessment types
(define-constant ASSESSMENT_PRE_SERVICE u1)
(define-constant ASSESSMENT_POST_SERVICE u2)

;; Data maps and variables
(define-map vehicle-registry (string-ascii 64) {
  owner: principal,
  make: (string-ascii 32),
  model: (string-ascii 32),
  year: uint,
  color: (string-ascii 16),
  vin: (string-ascii 17),
  license-plate: (string-ascii 16),
  registration-date: uint,
  is-active: bool
})

(define-map vehicle-assessments { vehicle-id: (string-ascii 64), service-id: uint, assessment-type: uint } {
  assessor: principal,
  assessment-date: uint,
  mileage: uint,
  overall-condition: uint,
  exterior-condition: uint,
  interior-condition: uint,
  engine-condition: uint,
  tire-condition: uint,
  paint-condition: uint,
  glass-condition: uint,
  chrome-condition: uint,
  damage-level: uint,
  damage-description: (string-ascii 512),
  photo-hashes: (list 10 (string-ascii 64)),
  assessment-notes: (string-ascii 1024),
  weather-conditions: (string-ascii 64),
  assessment-location: (string-ascii 256)
})

(define-map damage-reports { vehicle-id: (string-ascii 64), service-id: uint } {
  reporter: principal,
  report-date: uint,
  damage-type: (string-ascii 64),
  damage-severity: uint,
  damage-location: (string-ascii 128),
  damage-description: (string-ascii 512),
  estimated-repair-cost: uint,
  repair-required: bool,
  insurance-claim-needed: bool,
  evidence-hashes: (list 5 (string-ascii 64)),
  witness-accounts: (string-ascii 1024)
})

(define-map condition-comparisons { vehicle-id: (string-ascii 64), service-id: uint } {
  comparison-date: uint,
  pre-service-score: uint,
  post-service-score: uint,
  condition-change: int,
  damage-occurred: bool,
  improvements-noted: bool,
  comparison-notes: (string-ascii 512),
  assessor: principal,
  verification-status: bool
})

(define-map vehicle-maintenance-history (string-ascii 64) {
  last-service-date: uint,
  total-services: uint,
  total-damage-incidents: uint,
  average-pre-condition: uint,
  average-post-condition: uint,
  maintenance-alerts: (list 5 (string-ascii 128)),
  service-recommendations: (string-ascii 512)
})

(define-map assessment-authorizations { vehicle-id: (string-ascii 64), assessor: principal } {
  authorized-by: principal,
  authorization-date: uint,
  authorization-expiry: uint,
  assessment-scope: (string-ascii 256),
  is-active: bool
})

(define-data-var total-vehicles uint u0)
(define-data-var total-assessments uint u0)
(define-data-var total-damage-reports uint u0)
(define-data-var assessment-fee uint u50)
(define-data-var contract-active bool true)

;; Private functions
(define-private (is-valid-condition-score (score uint))
  (and (>= score MIN_CONDITION_SCORE) (<= score MAX_CONDITION_SCORE)))

(define-private (is-valid-damage-level (level uint))
  (<= level DAMAGE_SEVERE))

(define-private (calculate-condition-change (pre-score uint) (post-score uint))
  (- (to-int post-score) (to-int pre-score)))

(define-private (is-authorized-assessor (vehicle-id (string-ascii 64)) (assessor principal))
  (let ((auth-data (map-get? assessment-authorizations { vehicle-id: vehicle-id, assessor: assessor })))
    (match auth-data
      authorization (and (get is-active authorization) (> (get authorization-expiry authorization) block-height))
      false)))

(define-private (update-vehicle-maintenance-history (vehicle-id (string-ascii 64)) (pre-score uint) (post-score uint) (damage-occurred bool))
  (let ((current-history (default-to {
    last-service-date: u0,
    total-services: u0,
    total-damage-incidents: u0,
    average-pre-condition: u5,
    average-post-condition: u5,
    maintenance-alerts: (list),
    service-recommendations: ""
  } (map-get? vehicle-maintenance-history vehicle-id))))
    (let ((new-total-services (+ (get total-services current-history) u1))
          (new-damage-incidents (if damage-occurred (+ (get total-damage-incidents current-history) u1) (get total-damage-incidents current-history)))
          (new-avg-pre (/ (+ (* (get average-pre-condition current-history) (get total-services current-history)) pre-score) new-total-services))
          (new-avg-post (/ (+ (* (get average-post-condition current-history) (get total-services current-history)) post-score) new-total-services)))
      (map-set vehicle-maintenance-history vehicle-id
        (merge current-history {
          last-service-date: block-height,
          total-services: new-total-services,
          total-damage-incidents: new-damage-incidents,
          average-pre-condition: new-avg-pre,
          average-post-condition: new-avg-post
        })))))

;; Public functions
(define-public (register-vehicle (vehicle-id (string-ascii 64)) (make (string-ascii 32)) (model (string-ascii 32))
                                (year uint) (color (string-ascii 16)) (vin (string-ascii 17)) (license-plate (string-ascii 16)))
  (let ((owner tx-sender))
    (if (is-some (map-get? vehicle-registry vehicle-id))
      ERR_VEHICLE_NOT_FOUND
      (begin
        (map-set vehicle-registry vehicle-id {
          owner: owner,
          make: make,
          model: model,
          year: year,
          color: color,
          vin: vin,
          license-plate: license-plate,
          registration-date: block-height,
          is-active: true
        })
        (var-set total-vehicles (+ (var-get total-vehicles) u1))
        (ok vehicle-id)))))

(define-public (conduct-pre-service-assessment (vehicle-id (string-ascii 64)) (service-id uint) (mileage uint)
                                              (overall-condition uint) (exterior-condition uint) (interior-condition uint)
                                              (engine-condition uint) (tire-condition uint) (paint-condition uint)
                                              (glass-condition uint) (chrome-condition uint) (damage-level uint)
                                              (damage-description (string-ascii 512)) (photo-hashes (list 10 (string-ascii 64)))
                                              (assessment-notes (string-ascii 1024)) (weather-conditions (string-ascii 64))
                                              (assessment-location (string-ascii 256)))
  (let ((assessor tx-sender)
        (assessment-key { vehicle-id: vehicle-id, service-id: service-id, assessment-type: ASSESSMENT_PRE_SERVICE }))
    (if (is-some (map-get? vehicle-assessments assessment-key))
      ERR_ASSESSMENT_EXISTS
      (if (not (and (is-valid-condition-score overall-condition)
                   (and (is-valid-condition-score exterior-condition)
                        (and (is-valid-condition-score interior-condition)
                             (and (is-valid-condition-score engine-condition)
                                  (and (is-valid-condition-score tire-condition)
                                       (and (is-valid-condition-score paint-condition)
                                            (and (is-valid-condition-score glass-condition)
                                                 (and (is-valid-condition-score chrome-condition)
                                                      (is-valid-damage-level damage-level))))))))))
        ERR_INVALID_CONDITION_SCORE
        (begin
          (map-set vehicle-assessments assessment-key {
            assessor: assessor,
            assessment-date: block-height,
            mileage: mileage,
            overall-condition: overall-condition,
            exterior-condition: exterior-condition,
            interior-condition: interior-condition,
            engine-condition: engine-condition,
            tire-condition: tire-condition,
            paint-condition: paint-condition,
            glass-condition: glass-condition,
            chrome-condition: chrome-condition,
            damage-level: damage-level,
            damage-description: damage-description,
            photo-hashes: photo-hashes,
            assessment-notes: assessment-notes,
            weather-conditions: weather-conditions,
            assessment-location: assessment-location
          })
          (var-set total-assessments (+ (var-get total-assessments) u1))
          (ok assessment-key))))))

(define-public (conduct-post-service-assessment (vehicle-id (string-ascii 64)) (service-id uint) (mileage uint)
                                               (overall-condition uint) (exterior-condition uint) (interior-condition uint)
                                               (engine-condition uint) (tire-condition uint) (paint-condition uint)
                                               (glass-condition uint) (chrome-condition uint) (damage-level uint)
                                               (damage-description (string-ascii 512)) (photo-hashes (list 10 (string-ascii 64)))
                                               (assessment-notes (string-ascii 1024)) (weather-conditions (string-ascii 64))
                                               (assessment-location (string-ascii 256)))
  (let ((assessor tx-sender)
        (assessment-key { vehicle-id: vehicle-id, service-id: service-id, assessment-type: ASSESSMENT_POST_SERVICE })
        (pre-assessment-key { vehicle-id: vehicle-id, service-id: service-id, assessment-type: ASSESSMENT_PRE_SERVICE }))
    (if (is-none (map-get? vehicle-assessments pre-assessment-key))
      ERR_PRE_ASSESSMENT_MISSING
      (if (is-some (map-get? vehicle-assessments assessment-key))
        ERR_POST_ASSESSMENT_EXISTS
        (if (not (and (is-valid-condition-score overall-condition)
                     (and (is-valid-condition-score exterior-condition)
                          (and (is-valid-condition-score interior-condition)
                               (and (is-valid-condition-score engine-condition)
                                    (and (is-valid-condition-score tire-condition)
                                         (and (is-valid-condition-score paint-condition)
                                              (and (is-valid-condition-score glass-condition)
                                                   (and (is-valid-condition-score chrome-condition)
                                                        (is-valid-damage-level damage-level)))))))))
          ERR_INVALID_CONDITION_SCORE
          (let ((pre-assessment (unwrap-panic (map-get? vehicle-assessments pre-assessment-key))))
            (begin
              (map-set vehicle-assessments assessment-key {
                assessor: assessor,
                assessment-date: block-height,
                mileage: mileage,
                overall-condition: overall-condition,
                exterior-condition: exterior-condition,
                interior-condition: interior-condition,
                engine-condition: engine-condition,
                tire-condition: tire-condition,
                paint-condition: paint-condition,
                glass-condition: glass-condition,
                chrome-condition: chrome-condition,
                damage-level: damage-level,
                damage-description: damage-description,
                photo-hashes: photo-hashes,
                assessment-notes: assessment-notes,
                weather-conditions: weather-conditions,
                assessment-location: assessment-location
              })
              (let ((condition-change (calculate-condition-change (get overall-condition pre-assessment) overall-condition))
                    (damage-occurred (> damage-level (get damage-level pre-assessment))))
                (map-set condition-comparisons { vehicle-id: vehicle-id, service-id: service-id } {
                  comparison-date: block-height,
                  pre-service-score: (get overall-condition pre-assessment),
                  post-service-score: overall-condition,
                  condition-change: condition-change,
                  damage-occurred: damage-occurred,
                  improvements-noted: (> condition-change 0),
                  comparison-notes: "",
                  assessor: assessor,
                  verification-status: false
                })
                (update-vehicle-maintenance-history vehicle-id (get overall-condition pre-assessment) overall-condition damage-occurred))
              (var-set total-assessments (+ (var-get total-assessments) u1))
              (ok assessment-key)))))))

(define-public (report-damage (vehicle-id (string-ascii 64)) (service-id uint) (damage-type (string-ascii 64))
                             (damage-severity uint) (damage-location (string-ascii 128)) (damage-description (string-ascii 512))
                             (estimated-repair-cost uint) (repair-required bool) (insurance-claim-needed bool)
                             (evidence-hashes (list 5 (string-ascii 64))) (witness-accounts (string-ascii 1024)))
  (let ((reporter tx-sender)
        (damage-key { vehicle-id: vehicle-id, service-id: service-id }))
    (if (not (is-valid-damage-level damage-severity))
      ERR_INVALID_DAMAGE_LEVEL
      (begin
        (map-set damage-reports damage-key {
          reporter: reporter,
          report-date: block-height,
          damage-type: damage-type,
          damage-severity: damage-severity,
          damage-location: damage-location,
          damage-description: damage-description,
          estimated-repair-cost: estimated-repair-cost,
          repair-required: repair-required,
          insurance-claim-needed: insurance-claim-needed,
          evidence-hashes: evidence-hashes,
          witness-accounts: witness-accounts
        })
        (var-set total-damage-reports (+ (var-get total-damage-reports) u1))
        (ok damage-key)))))

(define-public (authorize-assessor (vehicle-id (string-ascii 64)) (assessor principal) (authorization-expiry uint) (assessment-scope (string-ascii 256)))
  (let ((vehicle-data (unwrap! (map-get? vehicle-registry vehicle-id) ERR_VEHICLE_NOT_FOUND)))
    (if (not (is-eq tx-sender (get owner vehicle-data)))
      ERR_UNAUTHORIZED
      (begin
        (map-set assessment-authorizations { vehicle-id: vehicle-id, assessor: assessor } {
          authorized-by: tx-sender,
          authorization-date: block-height,
          authorization-expiry: authorization-expiry,
          assessment-scope: assessment-scope,
          is-active: true
        })
        (ok assessor)))))

(define-public (revoke-assessor-authorization (vehicle-id (string-ascii 64)) (assessor principal))
  (let ((vehicle-data (unwrap! (map-get? vehicle-registry vehicle-id) ERR_VEHICLE_NOT_FOUND))
        (auth-key { vehicle-id: vehicle-id, assessor: assessor }))
    (if (not (is-eq tx-sender (get owner vehicle-data)))
      ERR_UNAUTHORIZED
      (let ((auth-data (unwrap! (map-get? assessment-authorizations auth-key) ERR_UNAUTHORIZED)))
        (map-set assessment-authorizations auth-key
          (merge auth-data { is-active: false }))
        (ok assessor)))))

;; Read-only functions
(define-read-only (get-vehicle-info (vehicle-id (string-ascii 64)))
  (map-get? vehicle-registry vehicle-id))

(define-read-only (get-vehicle-assessment (vehicle-id (string-ascii 64)) (service-id uint) (assessment-type uint))
  (map-get? vehicle-assessments { vehicle-id: vehicle-id, service-id: service-id, assessment-type: assessment-type }))

(define-read-only (get-damage-report (vehicle-id (string-ascii 64)) (service-id uint))
  (map-get? damage-reports { vehicle-id: vehicle-id, service-id: service-id }))

(define-read-only (get-condition-comparison (vehicle-id (string-ascii 64)) (service-id uint))
  (map-get? condition-comparisons { vehicle-id: vehicle-id, service-id: service-id }))

(define-read-only (get-vehicle-maintenance-history (vehicle-id (string-ascii 64)))
  (map-get? vehicle-maintenance-history vehicle-id))

(define-read-only (get-assessor-authorization (vehicle-id (string-ascii 64)) (assessor principal))
  (map-get? assessment-authorizations { vehicle-id: vehicle-id, assessor: assessor }))

(define-read-only (get-contract-stats)
  {
    total-vehicles: (var-get total-vehicles),
    total-assessments: (var-get total-assessments),
    total-damage-reports: (var-get total-damage-reports),
    assessment-fee: (var-get assessment-fee),
    contract-active: (var-get contract-active)
  })