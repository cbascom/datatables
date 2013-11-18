require 'spec_helper'

describe 'data_tables' do

  before :each do
    [ExceptOptionController, SearchTypeController].each do |controller|
      if DEBUG
        controller.any_instance.stub_chain(:logger, :debug){ |*args| puts args.first }
        controller.any_instance.stub_chain(:logger, :info){ |*args| puts args.first }
      else
        controller.any_instance.stub(:logger).and_return(double("Logger").as_null_object)
      end
      controller.any_instance.stub(:params).and_return({iSortCol_0: 1})
      controller.any_instance.stub(:render)
    end
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
  let(:search_type_instance){SearchTypeController.new.search_type_class_source}
  let(:index_name){ "#{Tire::Model::Search.index_prefix}dummy_class" }

  context "total records" do
    {"iTotalDisplayRecords" => 2, "iTotalRecords" => 2}.each do |k,v|
      it "respects datatables' except to calculate #{k} (#{v})" do
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

  context "mapping types sorting" do
    before do
      @data = %w[192.168.102.36:10.0.0.30 192.168.102.30 192.168.102.47]
      SearchTypeClass.index.delete
      SearchTypeClass.create_elasticsearch_index
      @data.each do |d|
        SearchTypeClass.create ipaddr: d, domain: :public
      end
      index_name = SearchTypeClass.index_name
      Tire.index(index_name){refresh}
    end

    it "sorts IP addresses asc correctly" do
      SearchTypeController.any_instance.stub(:params).and_return({
        iSortCol_0: 0,
        sSortDir_0: 'asc'
      })

      SearchTypeController.any_instance.should_receive(:render) do |*args|
        data = JSON.parse(args.first[:text])["aaData"]
        ips = data.map{|i| i[0]}
        ips.should == @data.sort
      end
      search_type_instance
    end

    it "sorts IP addresses desc correctly" do
      SearchTypeController.any_instance.stub(:params).and_return({
        iSortCol_0: 0,
        sSortDir_0: 'desc'
      })

      SearchTypeController.any_instance.should_receive(:render) do |*args|
        data = JSON.parse(args.first[:text])["aaData"]
        ips = data.map{|i| i[0]}
        ips.should == @data.sort.reverse
      end
      search_type_instance
    end
  end
end
