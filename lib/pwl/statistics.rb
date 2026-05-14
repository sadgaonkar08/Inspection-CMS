module Pwl
  module Statistics
    module_function

    def mean(values)
      raise ArgumentError, "no values" if values.empty?
      values.sum.to_f / values.size
    end

    # Sample standard deviation (n-1 denominator), per FAA C-110 §110-2.e.
    def sample_std_dev(values)
      n = values.size
      raise ArgumentError, "need at least 2 values" if n < 2
      m = mean(values)
      Math.sqrt(values.sum { |v| (v - m)**2 } / (n - 1).to_f)
    end
  end
end
