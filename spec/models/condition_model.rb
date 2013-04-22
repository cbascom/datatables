class DummyClass < Ohm::Model
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