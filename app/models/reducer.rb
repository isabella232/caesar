class Reducer < ApplicationRecord
  belongs_to :workflow

  validates_associated :extract_filter

  NoData = Class.new

  def process(extracts)
    filtered_extracts = extract_filter.filter(extracts)
    grouped_extracts = ExtractGrouping.new(filtered_extracts, grouping).to_h

    grouped_extracts.map do |key, grouped|
      [key, reduction_data_for(grouped)]
    end.to_h
  end

  def extract_filter
    ExtractFilter.new(filters)
  end

  def config
    super || {}
  end

  def filters
    super || {}
  end
end