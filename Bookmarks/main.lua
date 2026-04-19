utf8_to_html = require("utf8_to_html")

DEFAULT_EXPORT_PATH = "/tmp/temp"

-- Helper function to get mouse position
function get_mouse_position()
  local hasLgi, lgi = pcall(require, "lgi")
  if not hasLgi then return nil, nil end
  local pointer = lgi.Gdk.Display.get_default():get_default_seat():get_pointer()
  if not pointer then return nil, nil end
  local _, x, y = pointer:get_position()
  return x, y
end

-- Centralized Bookmark Parsing
function parse_bookmark(txt)
  local prefix, content = txt:match("^(%*)%s*(.*)")
  if not prefix then
    prefix, content = txt:match("^(%-+>)%s*(.*)")
  end
  return prefix, content
end

-- Centralized Bookmark Styling
function get_bookmark_style(text, defaultFontName)
  -- Strip out any existing variants including "Black"
  local baseFontFamily = defaultFontName:gsub(" Regular$", ""):gsub(" Bold$", ""):gsub(" Italic$", ""):gsub(" Black$", "")
  local fontName = baseFontFamily
  local fontSize = 25.0

  if text:match("^%*") then
    if baseFontFamily == "Segoe UI" then
      fontName = baseFontFamily .. " Black"
    else
      fontName = baseFontFamily .. " Bold"
    end
    fontSize = 25.0
  elseif text:match("^%-+>") then
    local depth = string.len(text:match("^(%-+)>"))
    if depth == 1 then
      if baseFontFamily == "Segoe UI" then
        fontName = baseFontFamily .. " Bold"
      else
        fontName = baseFontFamily .. " Regular"
      end
      fontSize = 20.0
    else
      fontName = baseFontFamily .. " Regular"
      fontSize = math.max(15.0, 20.0 - ((depth - 1) * 5.0))
    end
  end
  return fontName, fontSize
end

-- Register Toolbar
function initUi()
  app.registerUi({menu="Previous Bookmark", toolbarId="CUSTOM_PREVIOUS_BOOKMARK", callback="search_bookmark", mode=-1, iconName="go-previous"})
  app.registerUi({menu="New Bookmark", toolbarId="CUSTOM_NEW_BOOKMARK", callback="dialog_new_bookmark", iconName="bookmark-new-symbolic", ["accelerator"]="B"})
  app.registerUi({menu="New Bookmark (No dialog)", toolbarId="CUSTOM_NEW_BOOKMARK_NO_DIALOG", callback="new_bookmark", iconName="bookmark-new-symbolic"})
  app.registerUi({menu="Next Bookmark", toolbarId="CUSTOM_NEXT_BOOKMARK", callback="search_bookmark", mode=1, iconName="go-next"})
  app.registerUi({menu="View Bookmarks", toolbarId="CUSTOM_VIEW_BOOKMARKS", callback = "view_bookmarks", iconName="user-bookmarks-symbolic", ["accelerator"]="<Shift>B"})
  app.registerUi({menu="Export to PDF with Bookmarks", toolbarId="CUSTOM_EXPORT_WITH_BOOKMARKS", callback="export", iconName="xopp-document-export-pdf"})

  local sep = package.config:sub(1,1)
  sourcePath = debug.getinfo(1).source:match("@?(.*" .. sep .. ")")
  if sep == "\\" then DEFAULT_EXPORT_PATH = "%TEMP%\\temp" end
end

function new_bookmark(name)
  if not name or name == "" then return end

  local fontColor = 0x000000
  local fontName = "Sans Regular"
  
  local textToolInfo = app.getToolInfo("text")
  if textToolInfo then
    fontName = (textToolInfo.font and textToolInfo.font.name) or fontName
    fontColor = textToolInfo.color or fontColor
  end

  local newFontName, newFontSize = get_bookmark_style(name, fontName)

  -- Add the text and capture the reference so we can select it
  local refs = app.addTexts({
    texts = {
      { text = name, x = 20, y = 20, color = fontColor, font = { name = newFontName, size = newFontSize } }
    }
  })

  -- Automatically select the newly created bookmark
  if refs and #refs > 0 then
    local currentPage = app.getDocumentStructure().currentPage
    app.clearSelection()
    app.addToSelection(refs)
    app.scrollToPage(currentPage)
  end
end

function search_bookmark(mode)
  local allTexts = app.getTexts("all")
  if not allTexts then return end

  local bookmarkPages = {}
  for _, t in ipairs(allTexts) do
    if parse_bookmark(t.text or "") then bookmarkPages[t.page] = true end
  end

  local structure = app.getDocumentStructure()
  local numPages = #structure.pages
  local page = structure.currentPage

  for _ = 1, numPages do
    page = page + mode
    if page > numPages then page = 1 end
    if page < 1 then page = numPages end
    
    if bookmarkPages[page] then
      app.setCurrentPage(page)
      app.scrollToPage(page)
      return
    end
  end

  app.openDialog("No bookmark found.", {"Ok"}, "")
end

function dialog_new_bookmark()
  local hasLgi, lgi = pcall(require, "lgi")
  if not hasLgi then return new_bookmark() end

  local Gtk = lgi.require("Gtk", "3.0")
  local builder = Gtk.Builder()
  assert(builder:add_from_file(sourcePath .. "dlgNew.glade"))
  
  local ui = builder.objects
  local dialog = ui.dlgNew
  dialog:set_title("Xournalpp - New bookmark")
  ui.btnNewOk:set_sensitive(false)

  function ui.entryName:on_changed()
    ui.btnNewOk:set_sensitive(parse_bookmark(self:get_text()) ~= nil)
  end

  local function ok()
    local name = ui.entryName:get_text()
    if parse_bookmark(name) then
      new_bookmark(name)
      dialog:destroy()
    end
  end

  ui.btnNewOk.on_clicked = ok
  ui.entryName.on_activate = ok
  function ui.btnNewCancel:on_clicked() dialog:destroy() end

  local mouse_x, mouse_y = get_mouse_position()
  dialog:show_all()
  if mouse_x and mouse_y then
    dialog:move(mouse_x - dialog:get_allocated_width() / 2, mouse_y - dialog:get_allocated_height() / 2)
  end
end

function delete_bookmark(page, elementRef)
  if not elementRef then return end
  app.setCurrentPage(page)
  app.clearSelection()
  app.addToSelection({elementRef})
  app.activateAction("delete")
  app.clearSelection()
end

function view_bookmarks()
  local hasLgi, lgi = pcall(require, "lgi")
  if not hasLgi then
    return app.openDialog("Lua lgi-module is required to view bookmarks.", {"OK"}, "")
  end

  local Gtk = lgi.require("Gtk", "3.0")
  local builder = Gtk.Builder()
  assert(builder:add_from_file(sourcePath .. "dlgBookmarks.glade"))
  
  local ui, dialog = builder.objects, builder.objects.dlgBookmarks
  dialog:set_title("Xournalpp - Bookmarks Manager")

  local column = { PAGE = 1, PREFIX = 2, DISPLAY_NAME = 3, NAME = 4, REF = 5 }
  local store = Gtk.ListStore.new {
    [column.PAGE] = lgi.GObject.Type.UINT, [column.PREFIX] = lgi.GObject.Type.STRING,
    [column.DISPLAY_NAME] = lgi.GObject.Type.STRING, [column.NAME] = lgi.GObject.Type.STRING,
    [column.REF] = lgi.GObject.Type.POINTER
  }

  local function updateTable()
    store:clear()
    local allTexts = app.getTexts("all") or {}
    local bookmarks = {}

    for _, t in ipairs(allTexts) do
      local prefix, content = parse_bookmark(t.text or "")
      if prefix then
        table.insert(bookmarks, { page = t.page, prefix = prefix, displayName = content, name = t.text, ref = t.ref, y = t.y })
      end
    end

    table.sort(bookmarks, function(a, b) return a.page == b.page and a.y < b.y or a.page < b.page end)
    
    local currentPage = app.getDocumentStructure().currentPage
    local closest_exact_idx, closest_below_idx, closest_above_idx

    for i, b in ipairs(bookmarks) do 
      store:append({b.page, b.prefix, b.displayName, b.name, b.ref}) 
      
      -- Track nearest page indices based on Y-axis rules
      if b.page == currentPage then
        if not closest_exact_idx then closest_exact_idx = i end
      elseif b.page < currentPage then
        closest_below_idx = i -- continually updates, ending on the highest Y for this page
      elseif b.page > currentPage then
        if not closest_above_idx then closest_above_idx = i end -- locks on the lowest Y for this page
      end
    end

    -- Determine overall best index
    local best_idx = nil
    if closest_exact_idx then
      best_idx = closest_exact_idx
    else
      local dist_below = closest_below_idx and (currentPage - bookmarks[closest_below_idx].page) or math.huge
      local dist_above = closest_above_idx and (bookmarks[closest_above_idx].page - currentPage) or math.huge
      if dist_below <= dist_above and closest_below_idx then
        best_idx = closest_below_idx
      elseif closest_above_idx then
        best_idx = closest_above_idx
      end
    end

    return best_idx
  end

  local initial_best_idx = updateTable()

  local nameRenderer = Gtk.CellRendererText { editable = true }
  function nameRenderer:on_edited(path_str, new_text)
    local success, iter = store:get_iter(Gtk.TreePath.new_from_string(path_str))
    iter = type(success) == "userdata" and success or iter
    if not iter then return end
    
    local final_text = new_text:match("^%s*(.-)$") or ""
    local typed_prefix, typed_content = parse_bookmark(final_text)
    
    if not typed_prefix then
      local old_prefix = parse_bookmark(store[iter][column.NAME])
      if old_prefix then final_text = old_prefix .. " " .. final_text end
    else
      final_text = typed_prefix .. " " .. typed_content
    end

    if not parse_bookmark(final_text) then return app.openDialog("Invalid Bookmark", {"OK"}, "Must start with '*' or '->'.", true) end

    app.setCurrentPage(store[iter][column.PAGE])
    app.clearSelection()
    app.addToSelection({store[iter][column.REF]})
    
    local selTexts = app.getTexts("selection")
    if selTexts and #selTexts > 0 then
      local oldEl = selTexts[1]
      app.activateAction("delete")
      app.clearSelection()
      
      local newFontName, newFontSize = get_bookmark_style(final_text, oldEl.font.name or "Sans Regular")
      app.addTexts({ texts = { { text = final_text, x = oldEl.x, y = oldEl.y, color = oldEl.color, font = { name = newFontName, size = newFontSize } } } })
      updateTable()
    else
      app.clearSelection()
    end
  end

  -- Restored Declarative Syntax to prevent 0-indexing layout bug
  local treeView = Gtk.TreeView {
    model = store,
    Gtk.TreeViewColumn { 
      title = "Page", sizing = "FIXED", fixed_width = 50, 
      { Gtk.CellRendererText {}, {text = column.PAGE} } 
    },
    Gtk.TreeViewColumn { 
      title = "", sizing = "FIXED", fixed_width = 40, 
      { Gtk.CellRendererText {}, {text = column.PREFIX} } 
    },
    Gtk.TreeViewColumn {
      title = "Name",
      expand = true,
      {
        nameRenderer,
        {text = column.DISPLAY_NAME},
      }
    }
  }

  -- Manual Drag-to-Scroll implementation with Inertia Physics for Stylus users
  local drag_active = false
  local drag_start_y = 0
  local scroll_start_val = 0
  local last_y = 0
  local velocity = 0
  local scroll_tick = nil

  local function stop_inertia()
    if scroll_tick then
      lgi.GLib.source_remove(scroll_tick)
      scroll_tick = nil
    end
  end

  function treeView:on_button_press_event(event)
    if event.button == 1 then
      drag_active = true
      drag_start_y = event.y_root
      last_y = event.y_root
      scroll_start_val = ui.scrolledWindow:get_vadjustment():get_value()
      velocity = 0
      stop_inertia()
    end
    return false -- allow event to propagate to rows for selection/editing
  end

  function treeView:on_button_release_event(event)
    if event.button == 1 then 
      drag_active = false 
      if math.abs(velocity) > 1.5 then
        scroll_tick = lgi.GLib.timeout_add(lgi.GLib.PRIORITY_DEFAULT, 16, function()
          if drag_active then return false end
          
          local vadj = ui.scrolledWindow:get_vadjustment()
          local new_val = vadj:get_value() - velocity
          
          local lower_limit = vadj:get_lower()
          local upper_limit = vadj:get_upper() - vadj:get_page_size()
          
          if new_val <= lower_limit then 
            new_val = lower_limit
            velocity = 0 
          elseif new_val >= upper_limit then 
            new_val = upper_limit
            velocity = 0 
          end
          
          vadj:set_value(new_val)
          velocity = velocity * 0.90 -- Friction/Decay multiplier
          
          if math.abs(velocity) < 0.5 then
            scroll_tick = nil
            return false
          end
          return true
        end)
      end
    end
    return false
  end

  function treeView:on_motion_notify_event(event)
    if drag_active then
      velocity = event.y_root - last_y
      last_y = event.y_root
      
      local dy = drag_start_y - event.y_root
      local vadj = ui.scrolledWindow:get_vadjustment()
      vadj:set_value(scroll_start_val + dy)
      
      -- If we moved a noticeable amount, consume the event so we don't accidentally drag-select multiple rows
      if math.abs(dy) > 5 then return true end
    end
    return false
  end


  ui.scrolledWindow:add(treeView)

  function treeView:on_row_activated(path)
    local model, iter = self:get_model(), self:get_model():get_iter(path)
    if iter then
      local page = model[iter][column.PAGE]
      app.setCurrentPage(page)
      app.scrollToPage(page)
      app.clearSelection()
      app.addToSelection({model[iter][column.REF]})
      dialog:destroy()
    end
  end

  function ui.btnNew:on_clicked() new_bookmark(""); updateTable() end
  function ui.btnDelete:on_clicked()
    local model, iter = treeView:get_selection():get_selected()
    if iter then delete_bookmark(model[iter][column.PAGE], model[iter][column.REF]); updateTable() end
  end
    
  function dialog:on_destroy() stop_inertia() end

  function ui.btnDone:on_clicked() dialog:destroy() end

  local mx, my = get_mouse_position()
  dialog:show_all()
  if mx and my then dialog:move(mx - dialog:get_allocated_width() / 2, my - dialog:get_allocated_height() / 2) end

  -- Select and scroll to nearest bookmark upon opening the dialog
  if initial_best_idx then
    local path = lgi.Gtk.TreePath.new_from_string(tostring(initial_best_idx - 1))
    treeView:get_selection():select_path(path)
    treeView:scroll_to_cell(path, nil, true, 0.5, 0.0)
  end
end

function export()
  if not os.execute("pdftk") then return app.openDialog("pdftk is missing.", {"OK"}, "") end

  local structure = app.getDocumentStructure()
  local defaultName = (structure.xoppFilename and structure.xoppFilename:match("(.+)%..+$") or DEFAULT_EXPORT_PATH) .. "_export.pdf"
  local path = app.saveAs(defaultName)
  if not path then return end

  local sep = package.config:sub(1,1)
  local tempData = os.tmpname()
  if sep == "\\" then tempData = tempData:sub(2) end
  local tempPdf = tempData .. "_1337__.pdf"

  app.export({outputFile = tempPdf})
  os.execute("pdftk \"" .. tempPdf .. "\" dump_data output \"" .. tempData .. "\"")

  local bookmarks = {}
  local allTexts = app.getTexts("all") or {}
  
  for _, t in ipairs(allTexts) do
    if parse_bookmark(t.text or "") then
      table.insert(bookmarks, { page = t.page, name = utf8_to_html(t.text), y = t.y })
    end
  end
  
  table.sort(bookmarks, function(a, b) return a.page == b.page and a.y < b.y or a.page < b.page end)
  
  local file = io.open(tempData,"a+")
  for _, b in ipairs(bookmarks) do
    file:write("BookmarkBegin\nBookmarkTitle: " .. b.name .. "\nBookmarkLevel: 1\nBookmarkPageNumber: " .. b.page .. "\n")
  end
  file:close()

  os.execute("pdftk \"" .. tempPdf .. "\" update_info \"" .. tempData .. "\" output \"" .. path .."\"")
  os.remove(tempData)
  os.remove(tempPdf)
end