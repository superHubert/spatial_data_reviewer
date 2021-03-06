library(shiny)

source("../scripts/PACKAGES.R")
source("../scripts/get_interactive_map.R")
source("../scripts/get_ggplot_map.R")
source("../scripts/sp2geojsonList.R")
source("../scripts/HISTOGRAM.R")
source("../scripts/MISSINGS.R")
source("../scripts/SCATTERPLOT.R")
source("../scripts/TOP_CORRELATIONS.R")
source("../scripts/STEPWISE_VARS.R")

options(shiny.sanitize.errors = FALSE)
options(shiny.maxRequestSize=70*1024^2)

data <- NULL
pov_json_list <- NULL
pov_sp <- NULL

shinyServer(function(input, output){
  
  # suppress warnings  
  storeWarn <- getOption("warn")
  options(warn = -1) 

  data <- reactive({
    
    df <- upload()

    if(is.null(df)){
      return(NULL)
    }
    
    if(is.data.table(df) | tibble::is_tibble(df)){
      tryCatch({
        df <- as.data.frame(df)
      }, error = function(e) {
        showNotification("A file must readable as data.frame or data.table!",
                         type="error",
                         duration = 7)
        return(NULL)
      })
    }
    return(df)
    })
  
  
  match_data_map <- function(map, df, whichYearInput, whichSpIdInput, whichShpIdInput){
      # reorder data
      df <- df[match(as.character(map@data[,whichShpIdInput]), df[,whichSpIdInput]),]
      return(df)
  }
  
  
  # -------------------------------------------------- tab 1 -------------------------------------------------  
  
  # ---------------- INPUTS ---------------- 
  
  # year column name
  output$whichYear <- renderUI({
    
    data <- data()
    
    if(is.null(data)){
      return(NULL)
    } 
    
    choices <- names(data)  

    selectInput("whichYearInput", 
                label="Year Column",
                choices= choices,
                multiple = FALSE,
                )
    })
                

  # spatial unit name
  output$whichName <- renderUI({
    
    data <- data()
    
    if(is.null(data)){
      return(NULL)
    } 
    
    choices <- names(data) 
    
    selectInput("whichNameInput", 
                label="Unit name",
                choices = choices,
                multiple = FALSE
                )
  })
    
    
  # spatial unit identifyer
  output$whichSpID <- renderUI({
    
    data <- data()
    
    if(is.null(data)){
      return(NULL)
    } 
    
    choices <- names(data)  
    
    selectInput("whichSpIdInput", 
                label="Spatial ID",
                choices = choices,
                multiple = FALSE,
                )
  })
  
  # choose variable
  output$variableOutput <- renderUI({
    
    data <- data()
    
    if(is.null(data)){
      return(NULL)
    } 
    choices <- c("All", names(data))  
    selectInput("variableInput", 
                label="Variables",
                choices = choices,
                multiple = TRUE,
                selected = sample(choices,1)
                )
  })
  
  # choose area
  output$areaOutput <- renderUI({
    
    req(input$whichNameInput)
    data <- data()
    
    if(is.null(data)){
      return(NULL)}
    
    choices = if(!input$whichNameInput %in% names(data)) "All" else c("All", unique(data[,input$whichNameInput]))
    
    selectInput("areaInput",
                label="Area",
                choices = choices
                )
    })
  
  # choose range of years
  output$yearsOutput <- renderUI({
    
    data <- data()
    
    req(input$whichYearInput)
    
    if(is.null(data)){
      return(NULL)
    }
    
    if((input$fileType == 1 & grepl("(.rds)$|(.RDS)$", input$dataFile$datapath))|
       (input$fileType == 0 & grepl("(.csv)$|(.CSV)$", input$dataFile$datapath))|
       !grepl("(.csv)$|(.CSV)$|(.rds)$|(.RDS)$", input$dataFile$datapath)
    ){
      return(NULL)
    }
    
    start_y <- if(!(input$whichYearInput %in% names(data))) 0 else 
      if(!is.numeric(data[,input$whichYearInput])) 0 else 
        min(data[,input$whichYearInput]) 
    
    end_y <- if(!(input$whichYearInput %in% names(data))) 0 else 
      if(!is.numeric(data[,input$whichYearInput])) 0 else 
        max(data[,input$whichYearInput])
    
    sliderInput("inputYears", 
                label = "Years",
                step = 1,
                round=TRUE,
                sep="",
                min = start_y, 
                max = end_y,
                value = c(end_y-2, end_y)
                )
  }) 
  
  # ---------------- FUNCTIONS ---------------- 

  # file upload
  upload <- reactive({
    
    req(input$dataFile)
    
    if((input$fileType == 1 & grepl("(.rds)$|(.RDS)$", input$dataFile$datapath))|
       (input$fileType == 0 & grepl("(.csv)$|(.CSV)$", input$dataFile$datapath))|
       !grepl("(.csv)$|(.CSV)$|(.rds)$|(.RDS)$", input$dataFile$datapath) # to moze nie potrzebne
    ){
      
      showNotification("File format doesn't match the choice!",
                       type="error",
                       duration = 10)
      return(NULL)
    }
    
    if(input$fileType == 0 & grepl("(.rds)$|(.RDS)$", input$dataFile$datapath)){
      
      df <- readRDS(input$dataFile$datapath)
      
    } else if(input$fileType == 1 & grepl("(.csv)$|(.CSV)$", input$dataFile$datapath)){
      
      tryCatch({
        
        sep <- if(input$customSep != "") input$customSep else input$sep
        
        encoding = if(input$utf8) "UTF-8" else ""
        
        df <- read.csv(input$dataFile$datapath,
                       sep = sep,
                       dec = input$dec,
                       encoding = encoding,
                       stringsAsFactors = F)
        
      }, error = function(e) {
        showNotification("Probably wrong separator or other CSV upload setting!
                         Please tryanother separator.",
                         type="error",
                         duration = 10)
        return(NULL)
      })
    } else {
      return(NULL)
    }
  })
  
  # get data for table and plot
  filtered <- reactive({
    
    shiny::validate(
      need(!is.null(input$dataFile), "Remember to upload data file!")
    )
    
    # # do not show anyting at the beggining, otherwise error
    req(input$variableInput)
    
    years_chosen <- input$inputYears[1]:input$inputYears[2]
    units_chosen <- if(input$areaInput=="All") unique(data()[,input$whichNameInput]) else input$areaInput
    selected_columns <- if(input$variableInput=="All") names(data()) else 
      c(input$whichNameInput, input$whichSpIdInput, input$whichYearInput, input$variableInput)
    
    fitered_data1 <- data()[data()[,input$whichYearInput] %in% years_chosen &
                              data()[,input$whichNameInput] %in% units_chosen,
                            selected_columns]
    return(fitered_data1)
  })
  
  # function for displaying missingswhichYear
  missings_df <- reactive({
    
    shiny::validate(
      need(!is.null(input$dataFile), "Remember to upload data file!")
    )
    
    # filter data, filtered is reactive, thus will not be null, always gets generated
    req(input$variableInput)
    
    years_chosen <- input$inputYears[1]:input$inputYears[2]
    units_chosen <- if(input$areaInput=="All") unique(data()[,input$whichNameInput]) else input$areaInput
    selected_columns <- c(input$whichNameInput, input$whichSpIdInput, input$whichYearInput, input$variableInput)
    
    fitered_data <- data()[data()[,input$whichYearInput] %in% years_chosen &
                             data()[,input$whichNameInput] %in% units_chosen, 
                           selected_columns]
    
    # data frame for missing values, columns-years, rows-variables
    start_y <- if(!is.numeric(fitered_data[,input$whichYearInput])) 0 else 
      min(fitered_data[,input$whichYearInput]) 
    
    end_y <- if(!is.numeric(fitered_data[,input$whichYearInput])) 0 else 
      max(fitered_data[,input$whichYearInput])
    
    # print(max(fitered_data[,input$whichYearInput]))
    missing_n_col <- end_y - start_y + 1
    missings = as.data.frame(matrix(NA, ncol = missing_n_col, nrow = ncol(fitered_data)))
    
    j=1
    # add number of missing values in each year for each variable 
    for(i in seq(min(fitered_data[,input$whichYearInput]), max(fitered_data[,input$whichYearInput]),1)){
      
      # number of missing values in given year and variable
      col  = sapply(fitered_data[fitered_data[,input$whichYearInput]==i,], function(x) sum(is.na(x)))
      # input to right cell
      missings[,j] = col
      j=j+1
    }
    
    # name of columns as year
    colnames(missings) = seq(min(fitered_data[,input$whichYearInput]), max(fitered_data[,input$whichYearInput]), 1)
    
    # give NA column names
    rownames(missings) <- colnames(fitered_data)
    
    return(missings)
  }) 
  

  # ---------------- OUTPUTS ---------------- 
  
  
  # data output
  filtered_table <- eventReactive(input$filterData, filtered())
  output$dataOutput <- DT::renderDataTable({
    filtered_table()
  })
  
  # missing data table
  missings_table <- eventReactive(input$filterMissings, missings_df())
  output$missingsOutput <- DT::renderDataTable({
    missings_table()
  })
  
  
  # -------------------------------------------------- tab 2 -------------------------------------------------  
  
  # ---------------- INPUTS ---------------- 

  # spatial unit identifyer in shp file
  output$whichShpID <- renderUI({
    req(input$shapeFile)
    choices <- names(shpMap()@data)  
    selectInput("whichShpIdInput", 
                label="Shp units ID",
                choices = choices,
                multiple = FALSE)
  })
  
  # choose variable
  output$variableOutput2 <- renderUI({
    req(input$shapeFile, input$dataFile)
    selectInput("variableInput2", 
                label="Variable",
                choices = names(data())[5:length(names(data()))-1])

  })
  
  # choose single year 
  output$yearOutput2 <- renderUI({
    req(input$shapeFile, input$dataFile)
    selectInput("inputYear2", 
                label="Year",
                selected = 2018,
                choices = unique(data()[,input$whichYearInput]))

  }) 
  
  # choose title
  output$titleOutput <- renderUI({
    req(input$shapeFile, input$dataFile)
    Title <- if(is.null(input$variableInput2) | is.null(input$inputYear2)) "" else paste("Plot of", input$variableInput2 ,"in", input$inputYear2)
    textInput("inputTitle", 
              label="Title",
              value = Title
    )
  })
  
  # choose palette
  output$paletteOutput <- renderUI({
    selectInput("inputPalette",
                label="Palette",
                selected = "BuPu",
                choices = row.names(brewer.pal.info)
                )
  }) 
  
  # choose palette
  output$paletteOutput <- renderUI({
    selectInput("inputPalette",
                label="Palette",
                selected = "BuPu",
                choices = row.names(brewer.pal.info))
  }) 
  
  output$groupingType <- renderUI({
    req(input$shapeFile, input$dataFile)
    selectInput("groupingTypeInput",
                label = "Type of grouping",
                choices  = c("fixed", "sd", "equal", "pretty", "quantile",
                             "kmeans", "hclust", "bclust", "fisher", "jenks", "dpih"),
                selected = "pretty")
  })
  
  
  output$titleSize <- renderUI({
    req(input$shapeFile, input$dataFile)
    numericInput("titleSize",
                 label = "Title",
                 value = 15,
                 min = 8,
                 max = 20,
                 step = 1,
                 width = "100%")
    
  })

  output$legendTitleSize <- renderUI({
    req(input$shapeFile, input$dataFile)
    numericInput("legendTitleSize",
    label = "Legend",
    value = 13,
    min = 8,
    max = 20,
    step = 1,
    width = "100%")
    })


  output$legendLabelSize <- renderUI({
    req(input$shapeFile, input$dataFile)
    numericInput("legendLabelSize",
                 label = "Labels",
                 value = 12,
                 min = 8,
                 max = 20,
                 step = 1,
                 width = "100%"
                 )
    })

  # select seed to bclust or kmeans
  output$seedOutput <- renderUI({
    req(input$shapeFile, input$dataFile)
    textInput("seedInput",
              label = paste0(input$groupingTypeInput," seed"),
              value = 1)
  })
  
  
  # created text inputs for breaks, based on ranges of selected variable 
  output$fixedBreaksTexts <- renderUI({
    req(input$shapeFile, input$dataFile)
    
    variable <- data()[data()[,input$whichYearInput] == input$inputYear2, input$variableInput2]

    min_ <- min(variable)
    max_ <- max(variable)
    intermediate <- paste(rep("_", as.integer(input$ngroupsInput)-1), collapse = "  ")
    
    textInput("breaksInput",
              label = paste0("Breaks"),
              value = paste(min_, intermediate, max_, sep = "  ")) %>%
      shinyInput_label_embed(
        # add information icon with instruction
        icon("info") %>%
          bs_embed_tooltip(title = "Replace underscores with break values separated by space")
      )
  })
  
  
  output$staticMap <- renderUI({
    # req(input$shapeFile, input$dataFile)
    checkboxInput("staticMap",
                  label = "Static Map",
                  value = F
                  )
  })
  
  output$bucketingType <- renderUI({
    req(input$shapeFile, input$dataFile)
    radioButtons("bucketingTypeInput", label = "Bucketing mode",
                 choices = list("Automatic" = 0, "Manual" = 1),
                 selected = 0,
                 inline= T)
  })
  
  
  # ---------------- FUNCTIONS ----------------
  
  # function to extract numbers of breaks from breaksInput | this needs to be in reactive, because uses input that needs to be updates and
  # needs to return a value
  fixedBreaks <- reactive({
    # separate text inputs
    breaks <- as.numeric(unlist(stringr::str_split(input$breaksInput, pattern = "\\s+")))
  })
  
  shpMap <- reactive({
    
    req(input$shapeFile)
    # shpdf is a data.frame with the name, size, type and datapath
    # of the uploaded files
    shpdf <- input$shapeFile
    
    # Name of the temporary directory where files are uploaded
    tempdirname <- dirname(shpdf$datapath[1])
    
    # Rename files
    for (i in 1:nrow(shpdf)) {
      file.rename(
        shpdf$datapath[i],
        paste0(tempdirname, "/", shpdf$name[i])
      )
    }
    
    map <- readOGR(paste(tempdirname,
                         shpdf$name[grep(pattern = "*.shp$", shpdf$name)],
                         sep = "/"
    ), encoding = "UTF-8", stringsAsFactors = F)
    return(map)
  })
  
  json_list_map <- reactive({
    if(is.null(pov_json_list)){
      message("Json map is being loaded.")
      pov_json_list <- sp2geojsonList(shpMap())
      return(pov_json_list)
    }
  })
  
  ineractive_map <- reactive({
    
    shiny::validate(
      need(!is.null(input$dataFile) | !is.null(input$shapeFile), 
           "Remember to upload data and shape files!")
    )
    
    # initially no variabls, so map cannot be generated, so initially empty screen
    req(input$variableInput2)#, input$shapeFile)
    
    if(input$groupingTypeInput == "fixed"){
      
      # if fixed but automatic retun notification of error and do not still NULL
      if(input$bucketingTypeInput == 0){
        showNotification("Fixed type cannot be automatic!",
                         type="error",
                         duration = 7)
        return(NULL)
        
      } else {
        
        breaks <- fixedBreaks()
        
        # if breaks are not correct (not numbers, that were coerced to NA) notify and NULL
        if(anyNA(breaks)){
          showNotification("All breaks must be numeric!",
                           type="error",
                           duration = 7)
          return(NULL)
          
          # if fewer than expected breaks nofity error and return NULL
        } else if(length(breaks) != input$ngroupsInput+1){
          showNotification(paste0("Number of groups doesn't match number of breaks!\n Required ",
                                  input$ngroupsInput + 1," digits"),
                           type="error",
                           duration = 7)
          return(NULL)
        }
      }
    }
    
    # do not show anyting at the beggining, otherwise error
    dane <- data()[data()[,input$whichYearInput] == input$inputYear2,
                   c(input$whichNameInput,input$whichYearInput, input$whichSpIdInput, input$variableInput2)]
    
    dane <- match_data_map(shpMap(), dane, input$whichYearInput, input$whichSpIdInput, input$whichShpIdInput)
    
    shiny::validate(
      need(try(all(dane[,input$whichSpIdInput] == shpMap()@data[,input$whichShpIdInput])), "Some columns are not correctly specified.
      Make sure all `Data` tab inputs are correct, and `Spatial ID` and `Shp units ID` match each other!")
    )
    
    # if one recalculates the map in the same session, change number of groups
    if(input$bucketingTypeInput == 1){
      ngroupsInput <- input$ngroupsInput
    } else {
      ngroupsInput <- NULL
    }
    
    # read map first time function is used
    pov_json_list <- json_list_map()
    
    get_interactive_map(
      plot_data = dane,                        
      map_json = pov_json_list,                 
      mapped_variable = 4,                       
      joining_var = c(input$whichShpIdInput,
                      input$whichSpIdInput),
      groups_quantity = ngroupsInput,           
      title = input$inputTitle,                 
      bucketing_seed = input$seedInput,
      bucketing_type = input$groupingTypeInput, 
      breaks = breaks,
      colors_palette = input$inputPalette,      
      reverse_palette = input$reverseColor      
    )
  })
  
  
  static_map <- reactive({
    
    shiny::validate(
      need(!is.null(input$dataFile) | !is.null(input$shapeFile), "Remember to upload data and shape files!")
    )
    
    # initially no variabls, so map cannot be generated, so initially empty screen
    req(input$variableInput2)
    
    if(input$groupingTypeInput == "fixed"){
      
      # if fixed but automatic retun notification of error and do not still NULL
      if(input$bucketingTypeInput == 0){
        showNotification("Fixed type cannot be automatic!",
                         type="error",
                         duration = 7)
        return(NULL)
        
      } else {
        
        breaks <- fixedBreaks()
        
        # if breaks are not correct (not numbers, that were coerced to NA) notify and NULL
        if(anyNA(breaks)){
          showNotification("All breaks must be numeric!",
                           type="error",
                           duration = 7)
          return(NULL)
          
          # if fewer than expected breaks nofity error and return NULL
        } else if(length(breaks) != input$ngroupsInput+1){
          showNotification(paste0("Number of groups doesn't match number of breaks!\n Required ",
                                  input$ngroupsInput + 1," digits"),
                           type="error",
                           duration = 7)
          return(NULL)
        }
      }
    }
    
    # do not show anyting at the beggining, otherwise error
    dane <- data()[data()[,input$whichYearInput] == input$inputYear2,
                   c(input$whichNameInput,input$whichYearInput, input$whichSpIdInput, input$variableInput2)]
    
    # if one recalculates the map in the same session, change number of groups
    if(input$bucketingTypeInput == 1){
      ngroupsInput <- input$ngroupsInput
    } else {
      ngroupsInput <- NULL
    }
    
    # read map first time function is used
    shp_map <- shpMap()
    
    # match order of units in data and map
    dane <- match_data_map(shp_map, dane, input$whichYearInput, input$whichSpIdInput, input$whichShpIdInput)
    
    shiny::validate(
      need(try(all(dane[,input$whichSpIdInput] == shpMap()@data[,input$whichShpIdInput])), "Probably `Spatial ID` and `Shp units ID`
           are not correctly specified or their values do not match each other! 
           Make sure both files have corresponding ID variables!")
    )
    
    get_ggplot_map(
      plot_data = dane,                               
      map_sp = shp_map,                                 
      mapped_variable = 4,                            
      joining_var = c(input$whichShpIdInput,
                      input$whichSpIdInput),
      groups_quantity = ngroupsInput,                     
      bucketing_seed = input$seedInput,                           
      bucketing_type = input$groupingTypeInput,                 
      breaks = breaks,
      colors_palette = input$inputPalette,                  
      reverse_palette = input$reverseColor,                      
      title = input$inputTitle,
      title_size = input$titleSize,
      legend_title_size = input$legendTitleSize,
      legend_label_size = input$legendLabelSize
    )
  })
  

  # ---------------- OUTPUTS ----------------   
  
  
  interactive_map_plot <- eventReactive(input$filterAction2, ineractive_map())
  output$interactiveMapOutput <- renderHighchart({
    interactive_map_plot()
  })
  
  static_map_plot <- eventReactive(input$filterAction3, static_map())
  output$staticMapOutput <- renderPlot({
    static_map_plot()
  })
  
  output$palettes <- renderPlot({
    display.brewer.all()
  })
  
  # --- download ---
  
  # Downloadable csv of selected dataset ----
  output$downloadInteractMap <- downloadHandler(
    filename = function() {
      paste0(input$variableInput2, "_", input$inputYear2 ,".html")
    },
    content = function(file) {
      saveWidget(ineractive_map(), file)
    }
  )
  
  output$downloadggplotMap <- downloadHandler(
    filename = function() {
      paste0(input$variableInput2, "_", input$inputYear2 ,".png")
    },
    content = function(file) {
      ggsave(file, static_map(), width = 16, height = 12, units = "cm")
    }
  )
  
  
  # ----------------------------------------------------------------------------------------------------------
  # -------------------------------------------------- tab 3 -------------------------------------------------  
  # ----------------------------------------------------------------------------------------------------------
  
  # ---------------- INPUTS ---------------- 
   
  output$year <- renderUI({
    selectInput("year", 
                label = "Choose a year",
                choices = unique(data()[,input$whichYearInput]), 
                selected = 2018)
    })
  
  output$ExeptVar3 <- renderUI({
    selectInput("ExeptVar3",
                label = "Except",
                choices = colnames(data()),
                multiple = TRUE)
  })
  
  output$var <- renderUI({
    
    choices <- if(is.null(input$ExeptVar3)) colnames(data()) else 
      colnames(data())[-match(input$ExeptVar3, colnames(data()))]
    selectInput("var",
                label = "Choose a variable",
                choices = choices,
                )
    })
  
  output$var2 <- renderUI({
    
    choices <- if(is.null(input$ExeptVar3)) colnames(data()[-match(input$var, colnames(data()))]) else
      colnames(data())[-match(c(input$ExeptVar3, input$var), colnames(data()))]
    
    selectInput("var2",
                label = "Choose another variable for scatterplot",
                choices = choices
                )})
  
  
  # ---------------- FUNCTIONS ---------------- 
  

  get_analysis_plot <- reactive({
    
    shiny::validate(
      need(!is.null(input$dataFile) | !is.null(input$shapeFile), 
           "Remember to upload data and shape files!")
    )
    
    req(input$year, input$var, input$var2, input$bars)
    
    #all the input
    year = input$year
    var1 = input$var
    var2 = input$var2
    bars = input$bars
    
    #using one year only
    data_subset <- data()[data()[,input$whichYearInput]==input$year,]
    
    # get spatial weights matrix
    cont.listw <- get_weigth_matrix()
    
    #adjusting the histogram
    if(input$x_lower == '' | input$x_upper==''){
      x_lower = summary(data_subset[,match(var1, colnames(data_subset))])[1]
      x_upper = summary(data_subset[,match(var1, colnames(data_subset))])[6]
      
      x_lower = as.numeric(x_lower)
      x_upper = as.numeric(x_upper)
    }
    else{
      x_lower = as.numeric(input$x_lower)
      x_upper = as.numeric(input$x_upper)
    }
    
    tryCatch({
      
      #adjusted histogram
      his=nice_histogram(as.data.frame(data_subset), 
                         match(var1,colnames(data_subset)),
                         bars,
                         x_lower,
                         x_upper)
      
      #waffle plot with missing values
      mis=missings(as.data.frame(data_subset),
                   match(var1, colnames(data_subset))
      )
      
      #scatterplot
      sca=scatterplot(as.data.frame(data_subset), var1, var2)
      
      #calculates Morans's I and prepares a pie chart
      result01 <- moran.test(data_subset[,match(var1,colnames(data_subset))],
                             cont.listw)
      
      if(result01$estimate[1]>0){
        label = round(result01$estimate[1],4)
        moran_stat_df <- data.frame(groups=c('a','b'),
                                    values=c(result01$estimate[1],1-abs(result01$estimate[1])))
        dir=1
        col="#00b159"
      }
      if(result01$estimate[1]<0){
        label = round(result01$estimate[1],4)
        moran_stat_df <- data.frame(groups=c('a','b'),
                                    values=c(-result01$estimate[1],1+abs(result01$estimate[1])))
        dir=-1
        col="#d11141"
      }
      
      mor <- ggplot(moran_stat_df, aes(x="", y=values, fill=groups)) +
        geom_bar(stat="identity", width=1) +
        coord_polar("y", start=0, direction=dir) +
        theme_void() +
        scale_fill_manual(values = c(col,"#00aedb")) +
        ggtitle(paste("Moran's I for ",var1, sep='')) +
        theme(legend.position="none") +
        theme(plot.title = element_text(hjust = 0.5)) +
        geom_text(aes(y = values+0.1, label = c('',label)), color = 'white', size=7)
      
      #finds top 10 correlated variables (considering its absolute values)
      vars = find_best_predictors(data_subset, var1, input$ExeptVar3)
      
      #combined plot
      combined_plot <- grid.arrange(grobs=list(his, mor, sca, mis, tableGrob(vars, rows=NULL, theme=ttheme_minimal(base_size = 10))),
                                    layout_matrix = rbind(c(1,1,2,5),
                                                          c(3,3,4,5)))
      
      return(combined_plot)
    }, error = function(e) {
      showNotification("You might need to exempt non-quantitative columns or change file separator in Data tab.",
                       duration = 10)
      return(NULL)
    })
  })
  

  # ---------------- OUTPUTS ----------------   
  
  
  get_combined_plot <- eventReactive(input$getAnalysis, get_analysis_plot())
  output$plots <- renderPlot({
    get_combined_plot()
  })
  
  
  # ----------------------------------------------------------------------------------------------------------
  # -------------------------------------------------- tab 4 ------------------------------------------------- 
  # ----------------------------------------------------------------------------------------------------------
  
  # ---------------- INPUTS ---------------- 
  
  output$ChosenYear <- renderUI({
    selectInput("ChosenYear",
                label = "Year",
                choices = unique(data()[,input$whichYearInput]),
                selected = 2018)
    })
  
  output$ExeptVar4 <- renderUI({
    selectInput("ExeptVar4",
                label = "Except",
                choices = colnames(data()),
                multiple = TRUE)
    })
  
  output$DependentVariable <- renderUI({
    
    choices <- if(is.null(input$ExeptVar4)) colnames(data()) else 
      colnames(data())[-match(input$ExeptVar4, colnames(data()))]
    
    selectInput("DependentVariable",
                label = "Dependent variable",
                choices = choices)
    })
  
  output$IndependentVariables <- renderUI({
    
    choices <- if(is.null(input$ExeptVar4)) colnames(data()[-match(input$DependentVariable, colnames(data()))]) else
      colnames(data())[-match(c(input$ExeptVar4, input$DependentVariable), colnames(data()))]
    
    selectInput("IndependentVariables",
                label = "Independent variables",
                choices = choices,
                multiple = TRUE,
                selected = choices[1])
    })

  
  # ---------------- FUNCTIONS ---------------- 
  
  get_weigth_matrix <- reactive({
    cont.nb <- poly2nb(as(shpMap(), "SpatialPolygons"))
    cont.listw <- nb2listw(cont.nb, style="W")
  })
  
    # prepares models formula
    fitter <- reactive({
      
      shiny::validate(
        need(!is.null(input$dataFile) | !is.null(input$shapeFile), 
             "Remember to upload data and shape files!")
      )
      
      # get spatial weights matrix
      cont.listw <- get_weigth_matrix()
      
      req(input$ChosenYear, input$DependentVariable, input$IndependentVariables, input$bars)

      #prepares data subset
      data_subset = data()[data()[,input$whichYearInput]==input$ChosenYear,
                         match(c(input$DependentVariable, input$IndependentVariables), colnames(data()))]

      #classic
      if(input$Distance=='default: y~x'){
        model_formula = as.formula(
          paste(input$DependentVariable," ~ ",paste(input$IndependentVariables,
                                                    collapse="+")))
      }

      #multinomial
      if(input$Distance=='multinomial: y~x+x^2+x^3+x^4'){
        model_formula = as.formula(
          paste(input$DependentVariable," ~ ",paste(paste('poly(',input$IndependentVariables,',4)',sep=''),
                                                    collapse="+")))
      }

      #power
      if(input$Distance=='power: log(y)~log(x)'){
        model_formula = as.formula(
          paste(paste('log(',input$DependentVariable,'+1)',sep='')," ~ ",paste(paste('log(',input$IndependentVariables,'+1)',sep=''),
                                                                               collapse="+")))
      }

      #exponential
      if(input$Distance=='exponential: log(y)~x'){
        model_formula = as.formula(
          paste(input$DependentVariable," ~ ",paste(paste('log(',input$IndependentVariables,'+1)',sep=''),
                                                    collapse="+")))
      }

      #runs OLS
      if(input$ChosenModel=='ols'){
        fit <- lm(model_formula, data=data_subset)
      }

      #runs Manski model
      if(input$ChosenModel=='manski'){
        fit <- sacsarlm(model_formula,
                        data=data_subset,
                        listw=cont.listw,
                        type="sacmixed")
      }

      #runs SAC model
      if(input$ChosenModel=='sac'){
        fit <- sacsarlm(model_formula,
                        data=data_subset,
                        listw=cont.listw)
      }

      #runs SDEM model
      if(input$ChosenModel=='sdem'){
        fit <- errorsarlm(model_formula,
                          data=data_subset,
                          listw=cont.listw,
                          etype="emixed")
      }

      #runs SEM model
      if(input$ChosenModel=='sem'){
        fit <- errorsarlm(model_formula,
                          data=data_subset,
                          listw=cont.listw)
      }

      #runs SDM model
      if(input$ChosenModel=='sdm'){
        fit <- lagsarlm(model_formula,
                        data=data_subset,
                        listw=cont.listw,
                        type="mixed")
      }

      #runs SAR model
      if(input$ChosenModel=='sar'){
        fit <- lagsarlm(model_formula,
                        data=data_subset,
                        listw=cont.listw)
      }

      #runs SLX model
      if(input$ChosenModel=='slx'){
        fit <- lmSLX(model_formula,
                     data=data_subset,
                     listw=cont.listw)
      }
      return(fit)
    })

    recom <- reactive({
      
      shiny::validate(
        need(!is.null(input$dataFile) | !is.null(input$shapeFile), 
             "Remember to upload data and shape files!")
      )
      
      req(input$ChosenYear, input$DependentVariable, input$whichYearInput)
      
      data_subset = data()[data()[,input$whichYearInput]==input$ChosenYear,]

      except_columns <- input$ExeptVar4
      tryCatch({
        rec <- recommendation(data_subset,input$DependentVariable, except_columns)
        rec <- paste('Recommended variables are:', paste(rec, collapse = ", "))
        return(rec)
      }, error = function(e) {
        rec <- "Probably You need to exempt some non-quantitative columns like unit names, spatial IDs, year etc."
        return(rec)
      })
    })
    
    
    # ---------------- OUTPUTS ----------------   
    

    fit_model <- eventReactive(input$fitModel, summary(fitter()))
    output$evaluation <- renderPrint({
      fit_model()
    })
    
    get_var_recomend <- eventReactive(input$fitModel, recom())
    output$recommendation <- renderPrint({
      get_var_recomend()
    })
})






