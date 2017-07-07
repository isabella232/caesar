require 'spec_helper'

describe Reducers::CountReducer do
  def unwrap(reduction)
    reduction['_default']
  end

  let(:reducer) { described_class.new("s",{}) }

  it 'counts classifications' do
    expect(unwrap(reducer.process([]))).to include('classifications' => 0)
    expect(unwrap(reducer.process([Extract.new(classification_id: 1), Extract.new(classification_id: 1),
                            Extract.new(classification_id: 2), Extract.new(classification_id: 2)]))).to include('classifications' => 2)
  end

  it 'counts extracts' do
    expect(unwrap(reducer.process([]))).to include('extracts' => 0)
    expect(unwrap(reducer.process([Extract.new, Extract.new, Extract.new, Extract.new]))).to include('extracts' => 4)
  end
end
