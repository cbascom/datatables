require 'spec_helper'

describe 'data_tables' do
  before :each do
    if DEBUG
      ExceptOptionController.any_instance.stub_chain(:logger, :debug){ |*args| puts args.first }
      ExceptOptionController.any_instance.stub_chain(:logger, :info){ |*args| puts args.first }
    else
      ExceptOptionController.any_instance.stub(:logger).and_return(double("Logger").as_null_object)
    end
    ExceptOptionController.any_instance.stub(:params).and_return({})
    ExceptOptionController.any_instance.stub(:render)
    ActiveRecord::Base.stub_chain(:connection, :schema_search_path).and_return("public")
  end

  def save_elasticsearch(index_name, data)
    Tire.index(index_name) do
      unless exists?
        create mappings: {
          document: {
            properties: {
              name: { type: 'string' }
            }
          }
        }
      end
      data.each do |datum|
        store datum
      end
      refresh
    end
  end

  let(:instance){ExceptOptionController.new.dummy_class_source}
  let(:index_name){ "#{Tire::Model::Search.index_prefix}dummy_class" }

  context "Redis Models" do
    context "with ElasticSearch" do
      {"iTotalDisplayRecords" => 2, "iTotalRecords" => 2}.each do |k,v|
        it "respects datatables' except to calculate #{k} (#{v})" do
          # create index
          data = [{ id: 5002, name: 'not_valid', domain: 'public' },
                  { id: 561, name: 'Native AP VLAN', domain: 'public' },
                  { id: 56, name: 'valid', domain: 'public' }]
          save_elasticsearch(index_name, data)

          ExceptOptionController.any_instance.should_receive(:render) do |*args|
            arg = JSON.parse(args.first[:text])
            arg[k].should == v
          end
          instance
        end
      end
    end
  end
  context "Elastic Search Models" do
  end
  context "Postgres Models" do
  end
end
