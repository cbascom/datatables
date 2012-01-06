module DataTablesController
  def self.included(cls)
    cls.extend(ClassMethods)
  end
  
  module ClassMethods
    def datatables_source(action, model,  *attrs)
      modelCls = Kernel.const_get(model.to_s.split("_").collect(&:capitalize).join)
      modelAttrs = nil
      if modelCls.new.is_a? Ohm::Model
        modelAttrs = Hash[*modelCls.new.attributes.collect  { |v| [v.to_s, nil] }.flatten]
      else 
        modelAttrs = modelCls.new.attributes
      end
      columns = []
      modelAttrs.each_key { |k| columns << k }
      
      options = {}
      attrs.each do |option|
        option.each { |k,v| options[k] = v }
      end

      # override columns
      columns = options_to_columns(options) if options[:columns]
      
      conditions = options[:conditions] || []

      # define columns so they are accessible from the helper
      define_columns(modelCls, columns, action)
            
      # define method that returns the data for the table
      define_datatables_action(self, action, modelCls, conditions, columns)
    end

    def define_datatables_action(controller, action, modelCls, conditions, columns)      

      if modelCls.new.is_a? Ohm::Model
        define_method action.to_sym do
          domain = ActiveRecord::Base.connection.schema_search_path.to_s.split(",")[0]
          return if domain.nil? 
          search_condition = params[:sSearch].blank? ? nil : params[:sSearch].to_s
          total_records = (modelCls.find(:domain=>domain)).size
          sort_column = params[:iSortCol_0].to_i
          sort_column = 1 if sort_column == 0
          current_page = (params[:iDisplayStart].to_i/params[:iDisplayLength].to_i rescue 0) + 1
          objects = nil
          if search_condition.nil?
            objects = modelCls.find(:domain=>domain).sort_by(columns[sort_column][:name].to_sym, :order=>"ALPHA " + params[:sSortDir_0].capitalize, :limit=>params[:iDisplayLength].to_i, :start=>(params[:iDisplayStart].to_i)) 
            total_display_records =  total_records
          else
            objects = Lunar.search(modelCls, :domain=>domain, :fuzzy=>{columns[sort_column][:name].to_sym => search_condition})
            total_display_records = objects.size 
            objects = objects.sort(:by => columns[sort_column][:name].to_sym, :order=>"ALPHA " + params[:sSortDir_0].capitalize, :limit=>params[:iDisplayLength].to_i, :start=>(params[:iDisplayStart].to_i))
           end
           data = objects.collect do |instance|
              columns.collect { |column| datatables_instance_get_value(instance, column) }
           end
           render :text => {:iTotalRecords => total_records, 
                           :iTotalDisplayRecords => total_display_records,
                           :aaData => data, 
                           :sEcho => params[:sEcho].to_i}.to_json
       end
      else
        define_method action.to_sym do
          unless params[:sSearch].blank?
            search_conditions = []
            columns.find_all { |col| col.has_key?(:attribute) }.each do |col|
              search_conditions << "(text(#{col[:attribute]}) ILIKE '%%#{params[:sSearch]}%%')"
            end
            conditions << '(' + search_conditions.join(" OR ") + ')'
          end
           
          total_records = modelCls.count  
          total_display_records = modelCls.count :conditions => conditions
          
          sort_column = params[:iSortCol_0].to_i
          sort_column = 1 if sort_column == 0
          current_page = (params[:iDisplayStart].to_i/params[:iDisplayLength].to_i rescue 0)+1
          objects = modelCls.paginate(:page => current_page, 
                                      :order => "#{columns[sort_column][:name]} #{params[:sSortDir_0]}", 
                                      :conditions => conditions.join(" AND "),
                                      :per_page => params[:iDisplayLength])
          data = objects.collect do |instance|
            columns.collect { |column| datatables_instance_get_value(instance, column) }
          end
          render :text => {:iTotalRecords => total_records, 
                           :iTotalDisplayRecords => total_display_records,
                           :aaData => data, 
                           :sEcho => params[:sEcho].to_i}.to_json
        end
      end
    end
    
    private
    
    #
    # Takes a list of columns from options and transforms them
    #
    def options_to_columns(options)
      columns = []
      options[:columns].each do |column|
        if column.kind_of? Symbol # a column from the database, we don't need to do anything
          columns << {:name => column, :attribute => column}
        elsif column.kind_of? Hash
          columns << {:name => column[:name], :special => column}
        end
      end
      columns
    end
    
    def define_columns(cls, columns, action)
      define_method "datatable_#{action}_columns".to_sym do
        columnNames = []
       columns.each do |column|
         if column[:method] or column[:eval]
            columnNames << I18n.t(column[:name], :default => column[:name].to_s)
          else
            columnNames << I18n.t(column[:name].to_sym, :default => column[:name].to_s)
          end
        end
        columnNames
      end
    end
  end
  
  # gets the value for a column and row
  def datatables_instance_get_value(instance, column)
    if column[:attribute]
      val = instance.send(column[:attribute].to_sym)
      return I18n.t(val.to_s.to_sym, :default => val.to_s) if not val.nil?
      return ''
    elsif column[:special]
      special = column[:special]
      
      if special[:method]
        return method(special[:method].to_sym).call(instance)
      elsif special[:eval]
        proc = lambda { obj = instance; binding }
        return Kernel.eval(special[:eval], proc.call)
      end
    end
    return "value not found"
  end
  
  def datatable_source(name)
    {:action => name, :attrs => method("datatable_#{name}_columns".to_sym).call}
  end
end
