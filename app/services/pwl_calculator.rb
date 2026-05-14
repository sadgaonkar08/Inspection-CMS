class PwlCalculator
  Result = Struct.new(
    :status, :n, :mean, :std_dev,
    :lower_limit, :upper_limit,
    :q_lower, :q_upper, :p_lower, :p_upper,
    :pwl_percentage,
    keyword_init: true
  )

  STATUS_OK = :ok
  STATUS_INSUFFICIENT_N = :insufficient_n
  STATUS_N_TOO_LARGE = :n_too_large
  STATUS_MISSING_LIMITS = :missing_limits

  def initialize(values, lower_limit: nil, upper_limit: nil)
    @values = values.compact
    @lower_limit = lower_limit
    @upper_limit = upper_limit
  end

  def call
    n = @values.size
    return result(status: STATUS_INSUFFICIENT_N, n: n) if n < 3
    return result(status: STATUS_N_TOO_LARGE, n: n) if n > 10
    return result(status: STATUS_MISSING_LIMITS, n: n) if @lower_limit.nil? && @upper_limit.nil?

    mean = Pwl::Statistics.mean(@values)
    std_dev = Pwl::Statistics.sample_std_dev(@values)

    if std_dev.zero?
      pwl = within_limits?(mean) ? 100 : 0
      return result(status: STATUS_OK, n: n, mean: mean, std_dev: 0.0, pwl_percentage: pwl)
    end

    q_lower = @lower_limit && (mean - @lower_limit) / std_dev
    q_upper = @upper_limit && (@upper_limit - mean) / std_dev
    p_lower = q_lower && Pwl::QTable.lookup(q_lower, n)
    p_upper = q_upper && Pwl::QTable.lookup(q_upper, n)

    pwl =
      if p_lower && p_upper
        [(p_lower + p_upper) - 100, 0].max
      else
        p_lower || p_upper
      end

    result(
      status: STATUS_OK, n: n, mean: mean, std_dev: std_dev,
      q_lower: q_lower, q_upper: q_upper,
      p_lower: p_lower, p_upper: p_upper,
      pwl_percentage: pwl
    )
  end

  private

  def result(**fields)
    Result.new(lower_limit: @lower_limit, upper_limit: @upper_limit, **fields)
  end

  def within_limits?(value)
    (@lower_limit.nil? || value >= @lower_limit) && (@upper_limit.nil? || value <= @upper_limit)
  end
end
