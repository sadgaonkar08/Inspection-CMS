class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:microsoft_graph]

  enum role: { inspector: 0, qc: 1, admin: 2 }

  has_many :reports, dependent: :destroy
  has_many :imported_reports, dependent: :destroy
  has_many :weekly_reports, dependent: :destroy

  def full_name
    [first_name, last_name].map(&:presence).compact.join(" ").presence || email
  end

  def initials
    if first_name.present? && last_name.present?
      "#{first_name[0]}#{last_name[0]}".upcase
    else
      email[0..1].upcase
    end
  end

  # ── Email Allowlist (for local Devise sign-up) ──────────────────────
  ALLOWED_EMAILS = %w[
    admin@cms.com
    tester@cms.com
    rachelle@icms.com
    chris@icms.com
    dd@cms.com
    bh@cms.com
    dc@cms.com
    ja@cms.com
    sb@cms.com
    va@cms.com
  ].freeze

  def self.email_allowed?(email)
    ALLOWED_EMAILS.include?(email.to_s.strip.downcase)
  end

  # ── SSO helpers ─────────────────────────────────────────────────────

  # Find or create a user from Microsoft OmniAuth callback data.
  # On first SSO login, try to link to an existing local account by email
  # (preferred_username / UPN). If none exists, create a new SSO-only user.
  def self.from_microsoft_omniauth(auth)
    info  = auth.info
    extra = auth.extra&.raw_info || {}
    uid   = auth.uid
    pname = info.email.presence || extra["preferred_username"].presence || extra["upn"].presence
    oid   = extra["oid"]

    # 1) Already linked — fast path
    user = find_by(provider: "microsoft_graph", uid: uid)
    return user if user

    # 2) Link by matching email / preferred_username to existing local account
    user = find_by(email: pname) if pname.present?

    if user
      user.update!(provider: "microsoft_graph", uid: uid,
                   oid: oid, preferred_username: pname)
      return user
    end

    # 3) Brand-new SSO user (no local account match)
    create(
      provider: "microsoft_graph",
      uid: uid,
      oid: oid,
      preferred_username: pname,
      email: pname || "#{uid}@sso.placeholder",
      first_name: info.first_name.presence || extra["givenName"],
      last_name: info.last_name.presence || extra["surname"],
      password: Devise.friendly_token(32),   # random; they won't use local login
      role: :qc                              # default new SSO users to QC
    )
  end

  # Devise: allow SSO users (no password) to persist without password validation.
  def password_required?
    provider.blank? ? super : false
  end

  # Convenience predicate for admin role checks
  def admin?
    role == "admin"
  end

  # QC or Admin users may perform QC actions
  def can_qc?
    qc? || admin?
  end

  # Projects this user can see in filter dropdowns. QC/admin see everything;
  # inspectors are restricted to projects they have reports in, since
  # ReportsController#index already scopes their reports the same way.
  def accessible_projects
    if can_qc?
      Project.order(:name)
    else
      Project.where(id: reports.select(:project_id)).order(:name)
    end
  end

  # ── API Token Authentication ────────────────────────────────────────
  # Tokens are stored as bcrypt digests. The plaintext is shown once at
  # generation time and never persisted.

  # Generate a new random API token, store its digest, return plaintext.
  def generate_api_token!
    token = SecureRandom.hex(32) # 64-char hex string
    update!(api_token_digest: BCrypt::Password.create(token))
    token
  end

  # Look up user by API token (bearer token). Returns nil if no match.
  def self.authenticate_by_api_token(token)
    return nil if token.blank?
    find_each do |user|
      next unless user.api_token_digest.present?
      return user if BCrypt::Password.new(user.api_token_digest) == token
    end
    nil
  end
end
