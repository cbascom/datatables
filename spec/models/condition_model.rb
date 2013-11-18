class DummyClass < Ohm::Model
end

class SearchTypeClass
  include Tire::Model::Search
  include Tire::Model::Persistence

  property :name, type: 'string'
  property :ipaddr, type: 'string', index: 'not_analyzed'
  property :domain, type: 'string'
end

class ConditionModel
  include DataTablesController
  datatables_source(:dummy_class_source, :dummy_class,
                  :columns => [
                               {:name => "Actions",
                                 :method => :datatables_actions_column},
                               :name, :vlan, :cidr
                              ],
                  :conditions => ['id!=5002',"name!= 'Native AP VLAN'"])
end

class ExceptOptionController
  include DataTablesController
    datatables_source(:dummy_class_source, :dummy_class,
                    :columns => [
                                 {:name => "Actions",
                                   :method => :datatables_actions_column},
                                 :name, :state, :cidr, :vlan,
                                 {:name =>"Access Points",
                                   :method => :location_statuses_accesspoint_list}
                                ],:except => [['name','Native AP VLAN']])
end

class SearchTypeController
  include DataTablesController
  datatables_source(:search_type_class_source, :search_type_class,
                :columns => [:ipaddr, :name],
                :conditions => ['id!=5002',"name!= 'Native AP VLAN'"])
end
