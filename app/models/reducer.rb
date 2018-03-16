class Reducer < ApplicationRecord
  include Configurable

  enum topic: {
    reduce_by_subject: 0,
    reduce_by_user: 1
  }

  enum reduction_mode: {
    default_reduction: 0,
    running_reduction: 1
  }

  def self.of_type(type)
    case type.to_s
    when "consensus"
      Reducers::ConsensusReducer
    when "count"
      Reducers::CountReducer
    when 'placeholder'
      Reducers::PlaceholderReducer
    when "external"
      Reducers::ExternalReducer
    when "first_extract"
      Reducers::FirstExtractReducer
    when "stats"
      Reducers::StatsReducer
    when "summary_stats"
      Reducers::SummaryStatisticsReducer
    when "unique_count"
      Reducers::UniqueCountReducer
    else
      raise "Unknown type #{type}"
    end
  end

  belongs_to :workflow

  validates :workflow, presence: true
  validates :key, presence: true, uniqueness: {scope: [:workflow_id]}
  validates :topic, presence: true
  validates_associated :extract_filter

  before_validation :nilify_empty_fields

  NoData = Class.new

  def process(extracts, reductions=nil)
    light = Stoplight("reducer-#{id}") do
      grouped_extracts = ExtractGrouping.new(extracts, grouping).to_h

      keys = { workflow_id: workflow_id, reducer_key: key }
      keys[:subject_id] = extracts.first&.subject_id if reduce_by_subject?
      keys[:user_id] = extracts.first&.user_id if reduce_by_user?

      factory = if reduce_by_subject? then SubjectReduction elsif reduce_by_user? then UserReduction else nil end

      new_reductions = grouped_extracts.map do |group_key, grouped|
        keys[:subgroup] = group_key

        reduction = prepare_reduction(reductions, keys, factory)
        filtered_extracts = prepare_extracts(grouped, reduction)

        reduction_data = reduction_data_for(filtered_extracts, reduction)
        reduction.data = reduction_data if reduction.present?

        # note that because we use deferred associations, this won't actually hit the database
        # until the reduction is saved, meaning it happens inside the transaction
        associate_extracts(reduction, filtered_extracts) if running_reduction?

        if reduction_data == NoData
          Reducer::NoData
        else
          reduction
        end
      end

      if new_reductions == NoData || new_reductions.reject{|reduction| reduction==NoData}.empty?
        NoData
      else
        new_reductions
      end
    end

    light.run
  end

  def prepare_reduction(reductions, keys, factory)
    reduction = reductions&.where(keys)&.first_or_initialize
    reduction ||= factory.new(keys)

    # if reductions.present?
    #   reductions.where(keys).first_or_initialize
    # else
    #   factory.new(keys)
    # end.tap do |reduction|
    if running_reduction?
      reduction.data = {}
      reduction.store = {}
    else
      reduction.data ||= {}
      reduction.store ||= {}
    end
    # end
    reduction
  end

  def prepare_extracts(extract_group, reduction)
    filtered_extracts = extract_filter.filter(extract_group)
    seen_ids = reduction.extract_ids

    if running_reduction?
      filtered_extracts.reject{ |extract| seen_ids.include? extract.id }
    else
      filtered_extracts
    end
  end

  def associate_extracts(reduction, extracts)
    reduction.extract << extracts
  end

  def reduction_data_for(extracts, reduction)
    raise NotImplementedError
  end

  def get_reductions(keys)
    newkey = keys.merge(reducer_key: key).compact

    if reduce_by_subject?
      SubjectReduction.where(newkey.except(:user_id))
    elsif reduce_by_user?
      UserReduction.where(newkey.except(:subject_id))
    else
      nil
    end
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

  def nilify_empty_fields
    self.grouping = nil if grouping.blank?
  end
end
