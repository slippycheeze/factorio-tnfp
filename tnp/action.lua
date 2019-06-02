-- tnp_action_player_board()
--  Handles actions from a player boarding a requested tnp train.
function tnp_action_player_board(player, train)
    local config = settings.get_player_settings(player)

    if config['tnp-train-boarding-behaviour'].value == 'manual' then
        -- Force the train into manual mode, request is then fully complete.
        tnp_train_enact(train, true, nil, true, nil)
        tnp_request_cancel(player, train, nil)
    elseif config['tnp-train-boarding-behaviour'].value == 'stationselect' then
        -- Force the train into manual mode then display station select
        tnp_train_enact(train, true, nil, true, nil)
        tnp_gui_stationlist(player, train)
    end
end

-- tnp_action_player_cancel()
--   Actions a player cancelling a tnp request
function tnp_action_player_cancel(player, train)
    if not train.valid then
        -- We'd normally send a message, but because the trains invalid it'll be autogenerated from the prune task.
        tnp_request_cancel(player, train, nil)
        return
    end

    tnp_train_enact(train, true, nil, nil, false)
    tnp_request_cancel(player, train, {"tnp_train_cancelled"})
end

-- tnp_action_player_request()
--   Actions a player requesting a train
function tnp_action_player_request(player)
    local target = tnp_stop_find(player)

    if not target then
        tnp_message(tnpdefines.loglevel.core, player, {"tnp_train_nolocation"})
        return
    end

    tnp_request_create(player, target)
end

-- tnp_action_player_request_boarded()
--   Actions a player request from onboard a train
function tnp_action_player_request_boarded(player, train)
    local status = tnp_state_train_get(train, 'status')
    local train_player = tnp_state_train_get(train, 'player')

    if train_player and (not train_player.valid or train_player.index ~= player.index) then
        -- Special case where the train the players on now was assigned to another player.  This player wins.
        tnp_train_enact(train, true, nil, false, nil)
        tnp_request_cancel(train_player, train, {"tnp_train_cancelled_stolen", player.name})
    elseif status and status == tnpdefines.train.status.rearrived then
        -- Another special case where the train has already been redispatched and we're waiting for the
        -- player to disembark.  We need to reset the schedule before we reassign.
        tnp_train_enact(train, true, nil, false, nil)
    end

    tnp_request_assign(player, nil, train)
    tnp_action_player_board(player, train)
end

-- tnp_action_player_railtool()
--   Actions an area selection
function tnp_action_player_railtool(player, entities)
end

-- tnp_action_player_vehicle()
--   Handles actions from a player entering/exiting a vehicle
function tnp_action_player_vehicle(player, vehicle)
    local train = tnp_state_player_get(player, 'train')

    -- Player has entered a non-train vehicle, or we're not actually tracking them
    if vehicle and not vehicle.train or not train then
        return
    end

    if vehicle then
        -- Player has entered a vehicle.

        if not train.valid then
            -- The train we were tracking is now invalid, and will have a limbo schedule unfortunately.
            tnp_message(tnpdefines.loglevel.core, player, {"tnp_train_cancelled_invalid"})
            tnp_request_cancel(player, nil, nil)
        elseif train.id ~= vehicle.train.id then
            -- Player has boarded a different train.  Send the other train away (optional?)
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, {"tnp_train_cancelled_wrongtrain"})
        else
            -- Player has successfully boarded their tnp train
            local status = tnp_state_train_get(train, 'status')

            -- Player has boarded the train whilst we're dispatching -- treat that as an arrival.
            if status == tnpdefines.train.status.dispatching or status == tnpdefines.train.status.dispatched then
                tnp_action_train_arrival(player, train)
            end

            tnp_action_player_board(player, train)
        end
    else
        -- Player has exited a vehicle -- this could be anything.

        -- Attempt to close the stationlist regardless, just in case the players exited the train we sent
        tnp_gui_stationlist_close(player)

        -- We were tracking a train, but its no longer valid
        if not train.valid then
            tnp_request_cancel(player, train, nil)
            return
        end

        local status = tnp_state_train_get(train, 'status')

        -- It shouldn't be possible to exit a vehicle in a dispatching/dispatched status, as entering the vehicle
        -- would have triggered the boarding event.  We dont need to handle redispatched, as thats done via station
        -- wait conditions.
        if status == tnpdefines.train.status.arrived then
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, {"tnp_train_cancelled"})
        elseif status == tnpdefines.train.status.redispatched then
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, {"tnp_train_complete"})
        end
    end
end

-- tnp_action_railtool()
--   Provides the given player with a railtool
function tnp_action_railtool(player)
    -- Player already has a railtool in hand.
    if player.cursor_stack and player.cursor_stack.valid and player.cursor_stack.valid_for_read and player.cursor_stack.name == "tnp-railtool" then
        return
    end

    if not player.clean_cursor() then
        tpn_message_flytext(player, player.position, {"tnp_railtool_error_clear"})
        return
    end

    -- If the player has a railtool in their inventory, throw that one away
    local inventory = player.get_main_inventory()
    if inventory then
        local railtool = inventory.find_item_stack("tnp-railtool")
        if railtool then
            if not player.cursor_stack.swap_stack(railtool) then
                tnp_message_flytext(player, player.position, {"tnp_railtool_error_swap"})
            end

            return
        end
    end

	local result = player.cursor_stack.set_stack({
        name = "tnp-railtool",
        count = 1
    })
    if not result then
        tnp_message_flytext(player, player.position, {"tnp_railtool_error_provide"})
    end
end

-- tnp_action_stationselect_cancel()
--   Actions the stationselect dialog being cancelled
function tnp_action_stationselect_cancel(player)
    local train = tnp_state_player_get(player, 'train')

    tnp_gui_stationlist_close(player)

    -- We're still tracking a request at this point we need to cancel, though theres no
    -- schedule to amend.
    tnp_request_cancel(player, train, nil)
end

-- tnp_action_stationselect_redispatch()
--   Actions a stationselect request to redispatch
function tnp_action_stationselect_redispatch(player, gui)
    local station = tnp_state_gui_get(gui, player, 'station')
    local train = tnp_state_player_get(player, 'train')

    tnp_gui_stationlist_close(player)

    if not station or not station.valid then
        tnp_request_cancel(player, train, {"tnp_train_cancelled_invalidstation"})
        return
    end

    if not train or not train.valid then
        tnp_request_cancel(player, train, {"tnp_train_cancelled_invalid"})
    end

    -- Lets just revalidate the player is on a valid train
    if not player.vehicle or not player.vehicle.train or not player.vehicle.train.valid then
        tnp_request_cancel(player, train, {"tnp_train_cancelled_invalidstate"})
    end

    tnp_request_redispatch(player, station, player.vehicle.train)
end

-- tnp_action_train_arrival()
--   Partially fulfils a tnp request, marking a train as successfully arrived.
function tnp_action_train_arrival(player, train)
    tnp_state_train_delete(train, 'timeout')
    tnp_state_train_set(train, 'status', tnpdefines.train.status.arrived)
end

-- tnp_action_train_rearrival()
--   Partially fulfils a tnp request, marking a train as successfully arrived after redispatch.
function tnp_action_train_rearrival(player, train)
    -- From the players perspective the request is now complete so we need to cancel that side,
    -- but we must leave the train active as we cant reset its schedule until the player disembarks.
    tnp_request_cancel(player, nil, {"tnp_train_arrived"})
    tnp_state_train_set(train, 'status', tnpdefines.train.status.rearrived)
end

-- tnp_action_train_schedulechange()
--   Performs any checks and actions required when a trains schedule is changed.
function tnp_action_train_schedulechange(train, event_player)
    if event_player then
        -- The schedule was changed by a player, on a train we're dispatching.  We need to cancel this request
        local player = tnp_state_train_get(train, 'player')
        tnp_request_cancel(player, train, {"tnp_train_cancelled_schedulechange", event_player.name})
    else
        -- This is likely a schedule change we've made.  Check if we're expecting one.
        local expect = tnp_state_train_get(train, 'expect_schedulechange')
        if expect then
            tnp_state_train_set(train, 'expect_schedulechange', false)
            return
        end

        -- This is either another mod changing schedules of a train we're using, or our tracking is off.
        -- For now, do nothing -- though we should be able to verify its still going where we expect it to.
        -- !!!: TODO
    end
end

-- tnp_action_train_statechange()
--   Performs any checks and actions required when a trains state is changed.
function tnp_action_train_statechange(train)
    local player = tnp_state_train_get(train, 'player')
    local status = tnp_state_train_get(train, 'status')

    if not player or not player.valid then
        tnp_request_cancel(player, train, nil)
        return
    end

    if train.state == defines.train_state.on_the_path then
        -- TNfP Train is on the move event
        if status == tnpdefines.train.status.dispatching then
            -- This was a train awaiting dispatch
            tnp_state_train_set(train, 'status', tnpdefines.train.status.dispatched)
            tnp_message(tnpdefines.loglevel.standard, player, {"tnp_train_dispatched"})

        elseif status == tnpdefines.train.status.dispatched then
            -- This train had stopped for some reason.
            tnp_message(tnpdefines.loglevel.detailed, player, {"tnp_train_status_onway"})

        elseif status == tnpdefines.train.status.arrived then
            -- Train has now departed after arrival.  This could be a timeout, or someone has manually
            -- moved it to another station without changing the schedule.
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, {"tnp_train_cancelled_left"})

        elseif status == tnpdefines.train.status.rearrived then
            -- Train has now departed after rearrival.  The passenger has either disembarked, or someone
            -- moved it to another station without changing the schedule.  Either way we just reset
            -- the schedule.
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, nil)
        end

        -- elseif train.state == defines.train_state.path_lost then
        -- Train has lost its path.  Await defines.train_state.no_path
        -- elseif train.state == defines.train_state.no_schedule then
        -- Train has no schedule.  We'll handle this via the on_schedule_changed event

    elseif train.state == defines.train_state.no_path then
        -- Train has no path.
        -- If we're actively dispatching the train, we need to cancel it and restore its original schedule.
        if status == tnpdefines.train.status.dispatching or status == tnpdefines.train.status.dispatched then
            tnp_train_enact(train, true, nil, nil, false)
            tnp_request_cancel(player, train, {"tnp_train_cancelled_nopath"})

        -- Train has no path, but we need to restore the schedule anyway.
        elseif status == tnpdefines.train.status.arrived then
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, {"tnp_train_cancelled_timeout_boarding"})

        elseif status == tnpdefines.train.status.redispatched then
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, {"tnp_train_cancelled_nopath"})
        end
        -- elseif train.state == defines.train_state.arrive_signal
        -- Train has arrived at a signal.

    elseif train.state == defines.train_state.wait_signal then
        -- Train is now held at signals
        tnp_message(tnpdefines.loglevel.detailed, player, {"tnp_train_status_heldsignal"})

        -- elseif train.state == defines.train_state.arrive_station then
        -- Train is arriving at a station, await its actual arrival

    elseif train.state == defines.train_state.wait_station then
        -- Train has arrived at a station

        if status == tnpdefines.train.status.dispatching or status == tnpdefines.train.status.dispatched then
            -- This is an arrival to a station, after we've dispatched it.
            local station = tnp_state_train_get(train, 'station')

            -- The station we were dispatching to is no longer valid
            if not station or not station.valid then
                tnp_train_enact(train, true, nil, nil, nil)
                tnp_request_cancel(player, train, {"tnp_train_cancelled_invalidstation"})
                return
            end

            -- Our train has arrived at a different station.
            local station_train = station.get_stopped_train()
            if not station_train or not station_train.valid or not station_train.id == train.id then
                tnp_train_enact(train, true, nil, nil, false)
                tnp_request_cancel(player, train, {"tnp_train_cancelled_wrongstation"})
                return
            end

            tnp_message(tnpdefines.loglevel.standard, player, {"tnp_train_arrived"})
            tnp_action_train_arrival(player, train)

        elseif status == tnpdefines.train.status.redispatched then
            -- This was an redispatch station -- so wait for the passenger to disembark
            tnp_action_train_rearrival(player, train)
        end

    elseif train.state == defines.train_state.manual_control_stop or train.state == defines.train_state.manual_control then
        -- Train has been switched to manual control.  Handle these together, as if a train is already stopped
        -- we wont see defines.train_state.manual_control_stop.

        -- Check to see if we made this change ourselves
        local expect = tnp_state_train_get(train, 'expect_manualmode')
        if expect then
            -- if the train is stopping, do not clear the expectation as we will see both manual_control_stop and manual_control
            if train.state == defines.train_state.manual_control then
                tnp_state_train_set(train, 'expect_manualmode', false)
            end
            return
        end

        if status == tnpdefines.train.status.dispatching or status == tnpdefines.train.status.dispatched or status == tnpdefines.train.status.redispatched then
            -- If we're dispatching the train, we need to cancel the request and restore its original schedule
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, {"tnp_train_cancelled_manual"})

        elseif status == tnpdefines.train.status.arrived then
            -- Train had arrived, but we still need to restore the schedule.
            tnp_train_enact(train, true, nil, nil, nil)
            tnp_request_cancel(player, train, {"tnp_train_cancelled_manual"})
        end
    end
end

-- tnp_action_timeout()
--   Loops through trains and applies any timeout actions for dispatched trains.
function tnp_action_timeout()
    local trains = tnp_state_train_timeout()

    if not trains or #trains == 0 then
        return
    end

    for _, train in pairs(trains) do
        local player = tnp_state_train_get(train, 'player')
        local status = tnp_state_train_get(train, 'status')

        if status == tnpdefines.train.status.dispatching or status == tnpdefines.train.status.dispatched then
            tnp_train_enact(train, true, nil, nil, false)
            tnp_request_cancel(player, train, {"tnp_train_cancelled_timeout_arrival"})
        end
    end
end