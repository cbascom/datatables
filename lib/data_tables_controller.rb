module DataTablesController
  def self.included(cls)
    cls.extend(ClassMethods)
  end

  module ClassMethods
    def datatables_source(action, model,  *attrs)
      modelCls = Kernel.const_get(model.to_s.split("_").collect(&:capitalize).join)
      modelAttrs = nil
      if modelCls < Ohm::Model
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

      # define columns so they are accessible from the helper
      define_columns(modelCls, columns, action)

      # define method that returns the data for the table
      define_datatables_action(self, action, modelCls, columns, options)
    end

    # named_scope is a combination table that include everything shown in UI.
    # except is the codition used for Ohm's except method, it should be key-value format,
    # such as [['name', 'bluesocket'],['id','1']].
    def define_datatables_action(controller, action, modelCls, columns, options = {})
      conditions = options[:conditions] || []
      scope = options[:scope] || :domain
      named_scope = options[:named_scope]
      except = options[:except]

      if modelCls < Ohm::Model
        define_method action.to_sym do
          if scope == :domain
            domain = ActiveRecord::Base.connection.schema_search_path.to_s.split(",")[0]
            return if domain.nil?
          end
          search_condition = params[:sSearch].blank? ? nil : params[:sSearch].to_s
          records = scope == :domain ? modelCls.find(:domain => domain) : modelCls.all
          if except
            except.each do |f|
              records = records.except(f[0].to_sym => f[1])
            end
          end
          total_records = records.size
          sort_column = params[:iSortCol_0].to_i
          sort_column = 1 if sort_column == 0
          current_page = (params[:iDisplayStart].to_i/params[:iDisplayLength].to_i rescue 0) + 1
          objects = nil
          if search_condition.nil?
            objects = records.sort_by(columns[sort_column][:name].to_sym, :order=>"ALPHA " + params[:sSortDir_0].capitalize, :limit=>params[:iDisplayLength].to_i, :start=>(params[:iDisplayStart].to_i))
            total_display_records = total_records
          else
            options = {}
            domain_id = domain.split("_")[1].to_i if scope == :domain
            options[:domain] = domain_id .. domain_id if scope == :domain
            options[:fuzzy] = {columns[sort_column][:name].to_sym => search_condition}
            objects = Lunar.search(modelCls, options)
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
        # add_search_option will determine whether the search text is empty or not
        init_conditions = conditions.clone
        add_search_option = false
        define_method action.to_sym do
          condition_local = ''
          unless params[:sSearch].blank?
            search_conditions = []
            columns.find_all { |col| col.has_key?(:attribute) }.each do |col|
              condstr = params[:sSearch].gsub(/_/, '\\\\_').gsub(/%/, '\\\\%')
              search_conditions << "(text(#{col[:attribute]}) ILIKE '#{condstr}%')"
            end
            condition_local = '(' + search_conditions.join(" OR ") + ')'
          end

          # We just need one conditions string for search at a time.  Every time we input
          # something else in the search bar we will pop the previous search condition
          # string and push the new string.
          if condition_local != ''
            if add_search_option == false
              conditions << condition_local
              add_search_option = true
            else
              if conditions != []
                conditions.pop
                conditions << condition_local
              end
            end
          else
            if add_search_option == true
              if conditions != []
                conditions.pop
                add_search_option = false
              end
            end
          end

          if named_scope
            total_records = modelCls.send(named_scope).count :conditions => init_conditions.join(" AND ")
            total_display_records = modelCls.send(named_scope).count :conditions => conditions.join(" AND ")
          else
            total_records = modelCls.count :conditions => init_conditions.join(" AND ")
            total_display_records = modelCls.count :conditions => conditions.join(" AND ")
          end
          sort_column = params[:iSortCol_0].to_i
          sort_column = 1 if sort_column == 0
          current_page = (params[:iDisplayStart].to_i/params[:iDisplayLength].to_i rescue 0)+1
          if named_scope
              objects = modelCls.send(named_scope).paginate(:page => current_page,
                                          :order => "#{columns[sort_column][:name]} #{params[:sSortDir_0]}",
                                          :conditions => conditions.join(" AND "),
                                          :per_page => params[:iDisplayLength])
          else
              objects = modelCls.paginate(:page => current_page,
                                          :order => "#{columns[sort_column][:name]} #{params[:sSortDir_0]}",
                                          :conditions => conditions.join(" AND "),
                                          :per_page => params[:iDisplayLength])
          end
          #logger.info("------conditions is #{conditions}")
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
          columnName = ''
          if column[:method] or column[:eval]
            columnName << I18n.t(column[:name], :default => column[:name].to_s)
          else
            columnName << I18n.t(column[:name].to_sym, :default => column[:name].to_s)
          end
          columnName << ' *' unless column.has_key?(:attribute)
          columnNames << columnName
        end

        columnNames
      end
    end
  end

  # gets the value for a column and row
  def datatables_instance_get_value(instance, column)
    if column[:attribute]
      val = instance.send(column[:attribute].to_sym)
      return I18n.t(val.to_s.to_sym, :default => val.to_s) if not val.blank?
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
