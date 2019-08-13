class Reducer < ApplicationRecord
  include Configurable
  include BelongsToReducibleCached

  attr_reader :subject_id, :user_id

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
    when 'consensus'
      Reducers::ConsensusReducer
    when 'count'
      Reducers::CountReducer
    when 'placeholder'
      Reducers::PlaceholderReducer
    when 'external'
      Reducers::ExternalReducer
    when 'first_extract'
      Reducers::FirstExtractReducer
    when 'stats'
      Reducers::StatsReducer
    when 'summary_stats'
      Reducers::SummaryStatisticsReducer
    when 'unique_count'
      Reducers::UniqueCountReducer
    when 'rectangle'
      Reducers::AggregationReducers::RectangleReducer
    when 'sqs'
      Reducers::SqsReducer
    else
      raise "Unknown type #{type}"
    end
  end

  validates :key, presence: true, uniqueness: {scope: [:workflow_id]}
  validates :topic, presence: true
  validates_associated :extract_filter

  config_field :user_reducer_keys, default: nil
  config_field :subject_reducer_keys, default: nil

  NoData = Class.new

  def process(extracts, reductions, subject_id=nil, user_id=nil)
    @subject_id = subject_id
    @user_id = user_id

    light = Stoplight("reducer-#{id}") do
      grouped_extracts = ExtractGrouping.new(extracts, grouping).to_h
      grouped_extracts.map do |group_key, extract_group|
        reduction = get_group_reduction(reductions, group_key)
        extracts = filter_extracts(extract_group, reduction)

        # reduce the extracts into the correct reduction
        reduce_into(extracts, reduction).tap do |r|
          # if we are in running reduction, we never want to reduce the same extract twice so this
          # means that we must keep an association of which extracts are already part of a reduction
          if running_reduction?
              associate_extracts(r, extracts)
          end
        end
      end.select{ |reduction| reduction&.data&.present? }
    end

    light.run
  end

  def augment_extracts(extracts)
    relevant_reductions = get_relevant_reductions(extracts)
    if relevant_reductions.present?
      extracts.map do |ex|
        ex.relevant_reduction = if reduce_by_subject?
            relevant_reductions.find { |rr| rr.user_id == ex.user_id }
          elsif reduce_by_user?
            relevant_reductions.find { |rr| rr.subject_id == ex.subject_id }
          else
            raise NotImplementedError.new 'This reduction topic is not supported'
          end
      end
    end
  end

  def get_relevant_reductions(extracts)
    return [] unless reducer.user_reducer_keys.present? || reducer.subject_reducer_keys.present?

    if reduce_by_subject?
      UserReduction.where(user_id: extracts.map(&:user_id), reducible: reducible, reducer_key: reducer.user_reducer_keys)
    elsif reduce_by_user?
      SubjectReduction.where(subject_id: extracts.map(&:subject_id), reducible: reducible, reducer_key: reducer.subject_reducer_keys)
    else
      raise NotImplementedError.new 'This reduction mode is not supported'
    end
  end

  def filter_extracts(extracts, reduction)
    return extracts if extracts.blank?
    extracts = extract_filter.apply(extracts)
    extracts = extracts.reject{ |extract| reduction.extract_ids.include? extract.id }
  end

  def get_group_reduction(reductions, group_key)
    match = reductions.find{ |reduction| reduction.subgroup = group_key }
    if match.present?
      match
    else
      if reduce_by_subject?
        SubjectReduction.new \
          reducible: reducible,
          reducer_key: key,
          subgroup: group_key,
          subject_id: subject_id,
          data: {},
          store: {}
      elsif reduce_by_user?
        UserReduction.new \
          reducible: reducible,
          reducer_key: key,
          subgroup: group_key,
          user_id: user_id,
          data: {},
          store: {}
      else
        raise NotImplementedError.new 'This topic is not supported'
      end
    end
  end

  def associate_extracts(reduction, extracts)
    # note that because we use deferred associations, this won't actually hit the database
    # until the reduction is saved, meaning it happens inside the transaction
    extracts.each do |extract|
      reduction.extracts << extract
    end
  end

  def reduce_into(extracts, reduction)
    raise NotImplementedError
  end

  def extract_filter
    ExtractFilter.new(filters)
  end

  def stoplight_color
    @color ||= Stoplight("reducer-#{id}").color
  end

  def config
    super || {}
  end

  def filters
    super || {}
  end

  def grouping
    super || {}
  end

  def add_relevant_reductions(extracts, relevant_reductions)
    return extracts unless relevant_reductions.present?

  end
end
