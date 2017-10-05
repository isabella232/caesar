require 'spec_helper'

describe Reducers::SummaryStatisticsReducer do

  def unwrap(hash)
    hash["_default"]
  end

  let(:workflow){ create :workflow }

  describe '#configuration' do
    it 'requires configuration fields' do
      r1 = described_class.new(workflow_id: workflow.id, config: {})
      expect(r1).not_to be_valid
      expect(r1.errors[:summarize_field]).to be_present
      expect(r1.errors[:operations]).to be_present
    end
    it 'requires a valid field to summarize' do
      r1 = described_class.new(workflow_id: workflow.id, config: {"summarize_field" => "simple_field"})
      r2 = described_class.new(workflow_id: workflow.id, config: {"summarize_field" => "complex.field"})
      r1.validate
      r2.validate

      expect(r1.errors[:summarize_field]).not_to be_present
      expect(r2.errors[:summarize_field]).not_to be_present

      r3 = described_class.new(workflow_id: workflow.id, config: {"summarize_field" => "bad."})
      r3.validate

      expect(r3.errors[:summarize_field]).to be_present
    end

    it 'requires a valid list of operations' do
      r1 = described_class.new(workflow_id: workflow.id, config: {"operations" => 0})
      r1.validate
      expect(r1.errors[:operations]).to be_present

      r2 = described_class.new(workflow_id: workflow.id, config: {"operations" => "blah"})
      r2.validate
      expect(r2.errors[:operations]).to be_present

      r3 = described_class.new(workflow_id: workflow.id, config: {"operations" => "sum"})
      r3.validate
      expect(r3.errors[:operations]).not_to be_present

      r4 = described_class.new(workflow_id: workflow.id, config: {"operations" => []})
      r4.validate
      expect(r4.errors[:operations]).to be_present

      r5 = described_class.new(workflow_id: workflow.id, config: {"operations" => [0]})
      r5.validate
      expect(r5.errors[:operations]).to be_present

      r6 = described_class.new(workflow_id: workflow.id, config: {"operations" => ["blah"]})
      r6.validate
      expect(r6.errors[:operations]).to be_present

      r7 = described_class.new(workflow_id: workflow.id, config: {"operations" => ["sum"]})
      r7.validate
      expect(r7.errors[:operations]).not_to be_present

      r8 = described_class.new(workflow_id: workflow.id, config: {"operations" => ["sum", 0]})
      r8.validate
      expect(r8.errors[:operations]).to be_present

      r9 = described_class.new(workflow_id: workflow.id, config: {"operations" => ["sum", "blah"]})
      r9.validate
      expect(r9.errors[:operations]).to be_present

      r10 = described_class.new(workflow_id: workflow.id, config: {"operations" => ["sum", "average"]})
      r10.validate
      expect(r10.errors[:operations]).not_to be_present

    end

    it 'reads the config fields correctly' do
      r1 = described_class.new(workflow_id: workflow.id, config: {"summarize_field" => "simple_field"})
      r2 = described_class.new(workflow_id: workflow.id, config: {"summarize_field" => "complex.field"})

      expect(r1.send(:summarize_field)).to eq("simple_field")
      expect(r2.send(:summarize_field)).to eq("complex.field")

      expect(r1.send(:extractor_name)).to be_nil
      expect(r2.send(:extractor_name)).not_to be_nil
      expect(r2.send(:extractor_name)).to eq("complex")

      expect(r1.send(:field_name)).to eq("simple_field")
      expect(r2.send(:field_name)).to eq("field")

      r3 = described_class.new(workflow_id: workflow.id, config: {"operations" => ["sum", "average"]})
      expect(r3.send(:operations)).to eq(["sum", "average"])

      r4 = described_class.new(workflow_id: workflow.id, config: {"operations" => "sum"})
      expect(r4.send(:operations)).to eq(["sum"])
    end
  end

  describe '#reduction_data_for' do
    it 'considers only relevant extracts' do
      r1 = described_class.new(workflow_id: workflow.id, config: {"summarize_field" => "simple_field"})
      r2 = described_class.new(workflow_id: workflow.id, config: {"summarize_field" => "complex.field"})

      extracts = [
        create(:extract, extractor_key: "foo"),
        create(:extract, extractor_key: "complex"),
        create(:extract, extractor_key: "foo"),
        create(:extract, extractor_key: "complex"),
        create(:extract, extractor_key: "complex")
      ]

      allow(r1).to receive(:extracts).and_return(extracts)
      allow(r2).to receive(:extracts).and_return(extracts)

      expect(r1.send(:relevant_extracts)).to eq(extracts)
      expect(r2.send(:relevant_extracts)).not_to eq(extracts)
      expect(r2.send(:relevant_extracts).count).to eq(3)
    end

    it 'computes minimum correctly' do
      extracts = [
        create(:extract, data: {"some_field" => 4.7}),
        create(:extract, data: {"some_field" => "5"}),
        create(:extract, data: {"some_field" => 3}),
        create(:extract, data: {"some_other_field" => 2})
      ]

      reducer = described_class.new(config: {"summarize_field" => "some_field", "operations" => ["min"]})
      result = reducer.reduction_data_for(extracts)
      expect(result["min"]).to be_present
      expect(result["min"]).to eq(3)
    end

    it 'computes maximum correctly' do
      extracts = [
        create(:extract, data: {"some_field" => 4.7}),
        create(:extract, data: {"some_field" => "5"}),
        create(:extract, data: {"some_field" => 3}),
        create(:extract, data: {"some_other_field" => 2})
      ]

      reducer = described_class.new(config: {"summarize_field" => "some_field", "operations" => ["max"]})
      result = reducer.reduction_data_for(extracts)
      expect(result["max"]).to be_present
      expect(result["max"]).to eq(5)
    end

    it 'counts correctly' do
      extracts = [
        create(:extract, data: {"some_field" => 4.7}),
        create(:extract, data: {"some_field" => 4.7}),
        create(:extract, data: {"some_field" => "5"}),
        create(:extract, data: {"some_field" => 3}),
        create(:extract, data: {"some_other_field" => 2})
      ]

      reducer = described_class.new(config: {"summarize_field" => "some_field", "operations" => ["count"]})
      result = reducer.reduction_data_for(extracts)
      expect(result["count"]).to be_present
      expect(result["count"]).to eq(4)
    end

    it 'computes sum correctly' do
      extracts = [
        create(:extract, data: {"some_field" => 4.7}),
        create(:extract, data: {"some_field" => "5"}),
        create(:extract, data: {"some_field" => 3}),
        create(:extract, data: {"some_other_field" => 2})
      ]

      reducer = described_class.new(config: {"summarize_field" => "some_field", "operations" => ["sum"]})
      result = reducer.reduction_data_for(extracts)
      expect(result["sum"]).to be_present
      expect(result["sum"]).to eq(12.7)
    end

    it 'computes product correctly' do
      extracts = [
        create(:extract, data: {"some_field" => 4.7}),
        create(:extract, data: {"some_field" => "5"}),
        create(:extract, data: {"some_field" => 3}),
        create(:extract, data: {"some_other_field" => 2})
      ]

      reducer = described_class.new(config: {"summarize_field" => "some_field", "operations" => ["product"]})
      result = reducer.reduction_data_for(extracts)
      expect(result["product"]).to be_present
      expect(result["product"]).to eq(70.5)
    end

  end
end
