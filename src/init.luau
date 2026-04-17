--[[
	-- ValueBucket --

	v1.0.0
	
	An implementation of lazily evaluated token buckets in Luau.
	Useful for rate-limits and other depletion/regeneration use cases.
]]

--!strict
--!optimize 2

-- Imports --
const TypeUtils = require("@self/TypeUtils")
const Signal = require("@self/Signal")

-- ValueBucket Class --
const ValueBucket = {}
ValueBucket.__index = ValueBucket

type RawValueBucket = {
	MinValue: number?,
	MaxValue: number?,
	read Filling: boolean,
	read FillRate: number,
	
	-- Fired when the filling state changes.
	read FillingChanged: Signal.Signal<(filling: boolean) -> ()>,
	
	-- Fired when the fill rate changes.
	read FillRateChanged: Signal.Signal<(newFillRate: number) -> ()>,

	-- Fired when the value is manually changed via SetValue/AddValue/Consume.
	read ValueAdjusted: Signal.Signal<(newValue: number) -> ()>,
	
	-- Fired on any sort of value/fill change, useful for when scheduled events need to be retimed.
	-- Essentially a combinaton of all above events for convenience.
	read RetimingRequired: Signal.Signal<() -> ()>,
}

export type ValueBucket = setmetatable<RawValueBucket, typeof(ValueBucket)>

type RawInternalValueBucket = {
	_lastFill: number?, -- os.clock timestamp of the last auto-fill/drain.
	_value: number, -- Internal-only count of value, not for external use as this is only updated on method call
}

type InternalValueBucket = TypeUtils.internal<ValueBucket> & RawInternalValueBucket

const function clampValue(value: number, min: number?, max: number?): (number)
	if min then
		return if max
			then math.clamp(value, min, max)
			else math.max(value, min)
	elseif max then
		return math.min(value, max)
	end
	
	return value
end

--[[
	Returns the value clamped to min, safely handling nil.
]]
const function maxValue(value: number, min: number?): (number)
	if not min then
		return value
	end
	
	return math.max(value, min)
end

--[[
	Returns the value of the <code>ValueBucket</code>.
]]
function ValueBucket.GetValue(self: ValueBucket): (number)
	const iself: InternalValueBucket = self :: any
	
	local lastFill = iself._lastFill
	local minValue = self.MinValue
	local valueCount = maxValue(iself._value, minValue)
	
	-- Just return valueCount if not filling
	if not lastFill then
		return valueCount
	end
	
	local now = os.clock()
	local genValue = (now - lastFill) * self.FillRate
	
	valueCount = clampValue(valueCount + genValue, minValue, self.MaxValue)
	--self._value = valueCount
	
	return valueCount
end

--[[
	Sets the value of the <code>ValueBucket</code>.
]]
function ValueBucket.SetValue(self: ValueBucket, value: number): ()
	const iself: InternalValueBucket = self :: any

	value = value or 1

	iself._value = clampValue(value, self.MinValue, self.MaxValue)
	iself._lastFill = os.clock()
	self.ValueAdjusted:Fire(value)
	self.RetimingRequired:Fire()
end

--[[
	Sets the value fill rate of the <code>ValueBucket</code>.
]]
function ValueBucket.SetFillRate(self: ValueBucket, fillRate: number): ()
	const iself: InternalValueBucket = self :: any
	
	-- Generate value from the last fill rate before updating it
	local lastFill = iself._lastFill
	if lastFill then
		local now = os.clock()
		local genValue = (now - lastFill) * self.FillRate
		local minValue = self.MinValue
		
		iself._value = clampValue(maxValue(iself._value, minValue) + genValue, minValue, self.MaxValue)
		iself._lastFill = now
	end
	
	iself.FillRate = fillRate
	self.FillRateChanged:Fire(fillRate)
	self.RetimingRequired:Fire()
end

--[[
	Returns the real current fill rate of the <code>ValueBucket</code>, accounting for whether it is actually filling.
]]
function ValueBucket.GetCurrentFillRate(self: ValueBucket): (number)
	if self.Filling then
		return self.FillRate
	end
	
	return 0
end

--[[
	Starts automatically filling the <code>ValueBucket</code>.
]]
function ValueBucket.StartFilling(self: ValueBucket, rate: number?): ()
	const iself: InternalValueBucket = self :: any
	
	-- Update fill rate
	if rate then
		self:SetFillRate(rate)
	end
	
	-- Do nothing further if already Filling
	if self.Filling then return end
	
	iself.Filling = true
	iself._lastFill = os.clock()
	
	self.FillingChanged:Fire(true)
	self.RetimingRequired:Fire()
end

--[[
	Stops automatically filling the <code>ValueBucket</code>.
]]
function ValueBucket.StopFilling(self: ValueBucket): ()
	const iself: InternalValueBucket = self :: any
	
	local lastFill = iself._lastFill
	
	-- Do nothing if not Filling
	if not lastFill then return end
	
	local now = os.clock()
	local genValue = (now - lastFill) * self.FillRate
	local minValue = self.MinValue
	local totalValue = clampValue(maxValue(iself._value, minValue) + genValue, minValue, self.MaxValue)
	
	iself._value = totalValue
	iself.Filling = false
	
	self.FillingChanged:Fire(false)
	self.RetimingRequired:Fire()
end

--[[
	Adds value to the <code>ValueBucket</code>.
]]
function ValueBucket.AddValue(self: ValueBucket, value: number?): ()
	const iself: InternalValueBucket = self :: any

	value = value or 1
	
	local minValue = self.MinValue
	local totalValue = clampValue(maxValue(iself._value, minValue) + value, minValue, self.MaxValue)
	
	iself._value = totalValue
	self.ValueAdjusted:Fire(totalValue)
	self.RetimingRequired:Fire()
end

--[[
	Consumes value from the <code>ValueBucket</code> if there would be enough to still meet its minimum value afterwards.
	Returns a <code>boolean</code> indicating whether value was consumed, and the new value.
]]
function ValueBucket.Consume(self: ValueBucket, value: number?): (boolean, number)
	const iself: InternalValueBucket = self :: any
	
	value = value or 1
	
	local currValue = self:GetValue()
	if currValue < value then
		return false, currValue
	end
	
	-- also check for min value
	local minValue = self.MinValue
	if minValue and currValue - value < minValue then
		return false, currValue
	end
	
	-- always clamp just in case
	local totalValue = clampValue(currValue - value, minValue, self.MaxValue)
	iself._value = totalValue
	self.ValueAdjusted:Fire(totalValue)
	self.RetimingRequired:Fire()
	
	return true, totalValue
end

--[[
	Returns the number of seconds for the <code>ValueBucket</code> to reach <code>value</code> at its current fill rate.
	Can be negative if target goes in the opposite direction of fill rate, or infinite if fillRate is 0.
	
	<code><strong>ignoreFillingState</strong>: boolean?</code>
	Whether to ignore whether the <code>ValueBucket</code> is auto-filling and always return a number.
]]
function ValueBucket.GetTimeUntilValue(self: ValueBucket, targetValue: number?, ignoreFillingState: boolean?): (number)
	targetValue = targetValue or self.MaxValue or 1
	
	const currValue = self:GetValue()
	const delta = targetValue - currValue
	
	-- Already at value, so no time left
	-- Also prevents a possible NaN if fillRate is 0
	if delta == 0 then
		return 0
	end
	
	-- Will never reach target, so infinite time.
	if not ignoreFillingState and not self.Filling then
		return math.huge
	end
	
	const fillRate = self.FillRate
	const tTarg = delta / fillRate
	return tTarg
end

--[[
	Destroys the <code>ValueBucket</code>.
]]
function ValueBucket.Destroy(self: ValueBucket)
	self.FillingChanged:Destroy()
	self.FillRateChanged:Destroy()
	self.ValueAdjusted:Destroy()
	self.RetimingRequired:Destroy()
	table.clear(self)
	setmetatable(self, nil)
end

-- Module --
const interface = {}

--[[
	Returns a new <code>ValueBucket</code>.
]]
function interface.new(minValue: number?, maxValue: number?, fillRate: number?): (ValueBucket)
	const valueBucket: RawInternalValueBucket & RawValueBucket = {
		MinValue = minValue,
		MaxValue = maxValue,
		Filling = false,
		FillRate = fillRate or 0,
		FillingChanged = Signal.new() :: any,
		FillRateChanged = Signal.new() :: any,
		ValueAdjusted = Signal.new() :: any,
		RetimingRequired = Signal.new() :: any,
		_value = maxValue or minValue or 0,
	}
	
	return setmetatable(valueBucket, ValueBucket)
end

return interface