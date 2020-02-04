import math
from typing import Optional

import numpy as np
from numpy import reshape
from numpy.core.multiarray import ndarray

import NeuralNetwork.nn.core as core
import NeuralNetwork.nn.quant as quant


class Layer:
    """
    Abstract base class for a neural network layer instance
    """

    def __call__(self, *args, **kwargs):
        raise NotImplementedError()

    def backprop(self, *args):
        raise NotImplementedError()

    def update_weights(self, *args):
        raise NotImplementedError()

    def __add__(self, other: object) -> list:
        """
        Combine them in a list
        :param other:
        :return:
        """
        return [self, other]

    def get_input_shape(self):
        """
        Get the valid shape of input data for this layer
        :return: a tuple with the valid dimensions
        """
        raise NotImplementedError()

    def get_output_shape(self, input_data_shape: ndarray = None):
        """
        Get the shape of the output data with respect to input data of this layer
        :param input_data_shape: An optional input tensor
        :return: a tuple with the valid dimensions
        """
        raise NotImplementedError()

    def cast(self, new_dtype):
        """
        Casts the layer to new datatype (no copy)
        Args:
            new_dtype: the new data type that should be casted to

        Returns:
            None
        """
        pass

    def __copy__(self):
        """
        Create a copy of the layer object and returns it
        If not implemented this returns a copy to self
        Returns:
            A copy of the the layer
        """
        return self

    def deepcopy(self):
        """
        Creates a deep copy of the layer
        Returns:
            A deep copy of the object

        """
        return self.__copy__()

    def quantize_layer(self, target_type, fraction_bits, zero_point):
        pass


class FunctionalLayer(Layer):
    pass


class ParameterizedLayer(Layer):
    pass


class FullyConnectedLayer(Layer):
    activation: Optional[str]
    W: ndarray  # Weights of the layer, dimensions: [IN x OUT]
    b: ndarray  # bias of the layer

    @property
    def weights(self):
        return self.W

    @weights.setter
    def weights(self, value):
        assert isinstance(value, np.ndarray)
        self.W = value

    @property
    def bias(self):
        return self.b

    @bias.setter
    def bias(self, value):
        assert isinstance(value, np.ndarray)
        self.b = value

    @property
    def activation_func(self):
        return self.activation

    @activation_func.setter
    def activation_func(self, value):
        assert value in ('relu', 'softmax', None)
        self.activation = value

    def __init__(self, input_size, output_size, activation=None, dtype=np.float32, weights=None, bias=None):
        self.input_size = input_size
        self.output_size = output_size
        self.activation = activation
        self.dtype = dtype

        if weights is None:
            self.W = np.random.rand(input_size, output_size).astype(dtype=dtype)
        else:
            assert isinstance(weights, np.ndarray)
            assert np.all(weights.shape == (input_size, output_size))
            self.W = weights

        if bias is None:
            self.b = np.random.rand(output_size).astype(dtype=dtype)
        else:
            assert isinstance(bias, np.ndarray)
            self.b = bias

    def __call__(self, *args, **kwargs):
        # use the '@' sign to refer to a tensor dot
        # calculate z = xW + b
        z = np.matmul(args[0], self.W) + self.b

        if self.activation is None:
            return z
        elif self.activation is "relu":
            # return np.apply_over_axis(relu, z, 1)
            return core.relu(z)
        elif self.activation is "softmax":
            # return np.apply_over_axis(softmax, z, 1)
            return core.softmax(z)
        else:
            raise ValueError("Activation of {} is not valid".format(self.activation))

    def get_input_shape(self):
        return self.W.shape[0], -1

    def get_output_shape(self, input_data_shape: ndarray = None):
        return self.W.shape[1], -1

    def cast(self, new_dtype: np.dtype):
        self.dtype = new_dtype
        self.W = self.W.astype(dtype=new_dtype)
        self.b = self.b.astype(dtype=new_dtype)

    def __copy__(self):
        c = FullyConnectedLayer(input_size=self.input_size,
                                output_size=self.output_size,
                                dtype=self.dtype,
                                weights=self.W.copy(),
                                bias=self.b.copy())
        return c

    def quantize_layer(self, target_type, fraction_bits, zero_point):
        self.dtype = target_type
        self.W = quant.quantize_vector(self.W, target_type=target_type, max_value=max_value, min_value=min_value)
        self.b = quant.quantize_vector(self.b, target_type=target_type, max_value=max_value, min_value=min_value)


class MaxPool2dLayer(Layer):
    PoolSize: int

    def __init__(self, size=2):
        self.PoolSize = size

    def __call__(self, *args, **kwargs):
        data_in = args[0]
        return core.pooling_max(data_in, pool_size=self.PoolSize, stride=self.PoolSize)

    def get_input_shape(self):
        # Input is completely arbitrary
        return -1, -1, -1, -1

    def get_output_shape(self, input_data_shape: ndarray = None):
        # Input data:  [batch, in_height, in_width, in_channels]
        batch, in_w, in_h, nch = input_data_shape.shape
        out_w = math.ceil(in_w / self.PoolSize)
        out_h = math.ceil(in_h / self.PoolSize)
        return -1, out_w, out_h, -1

    def __copy__(self):
        return MaxPool2dLayer(size=self.PoolSize)


class AveragePool2dLayer(Layer):
    PoolSize: int

    def __init__(self, size=2):
        self.PoolSize = size

    def __call__(self, *args, **kwargs):
        data_in = args[0]
        return core.apply_pool(data_in, pool_size=self.PoolSize, f=np.mean)

    def get_input_shape(self):
        # Input is completely arbitrary
        return -1, -1, -1, -1

    def get_output_shape(self, input_data_shape: ndarray = None):
        # Input data:  [batch, in_height, in_width, in_channels]
        batch, in_w, in_h, nch = input_data_shape.shape
        out_w = math.ceil(in_w / self.PoolSize)
        out_h = math.ceil(in_h / self.PoolSize)
        return -1, out_w, out_h, -1

    def __copy__(self):
        return AveragePool2dLayer(size=self.PoolSize)


class Conv2dLayer(Layer):
    activation: Optional[str]
    b: ndarray
    kernel: ndarray

    def __init__(self,
                 in_channels,
                 out_channels,
                 kernel_size,
                 activation=None,
                 dtype=np.float32,
                 kernel_init_weights=None,
                 bias_init_weights=None):

        self.in_channels = in_channels
        self.out_channels = out_channels
        self.kernel_size = kernel_size
        self.activation = activation
        self.dtype = dtype

        if kernel_init_weights is None:
            self.kernel = core.init_kernel(in_channels, out_channels, kernel_size, dtype=dtype)
        else:
            self.kernel = kernel_init_weights

        if bias_init_weights is None:
            self.b = np.random.rand(out_channels).astype(dtype=dtype)
        else:
            self.b = bias_init_weights

    @property
    def weights(self):
        return self.kernel

    @weights.setter
    def weights(self, value):
        assert isinstance(value, np.ndarray)
        self.kernel = value

    @property
    def bias(self):
        return self.b

    @bias.setter
    def bias(self, value):
        assert isinstance(value, np.ndarray)
        self.b = value

    @property
    def activation_func(self):
        return self.activation

    @activation_func.setter
    def activation_func(self, value):
        assert value in ('relu', 'softmax', None)
        self.activation = value

    def __call__(self, *args, **kwargs):
        if self.dtype in (np.float32, np.float64):
            try:
                z = core.conv2d_fast(args[0], self.kernel, stride=1) + self.b
            except ImportError as imerror:
                print("[ERROR]: The Fast C-Extension could not be loaded? Is it installed? Fallback to default python "
                      "implementation")
                z = core.conv2d(args[0], self.kernel, stride=1) + self.b

        else:
            z = core.conv2d(args[0], self.kernel, stride=1) + self.b

        if self.activation is None:
            return z
        elif self.activation is "relu":
            return core.relu(z)
        else:
            raise ValueError("Activation of {} is not valid".format(self.activation))

    def get_input_shape(self):
        # Input data:  [batch, in_height, in_width, in_channels]
        # Kernel size: [fh, fw, kin_ch, kout_ch]
        #
        # Data can be arbitrary shaped except the number of input channels, which must match the number of output
        # channels
        return -1, -1, -1, self.kernel.shape[2]

    def get_output_shape(self, input_data_shape: ndarray = None):
        # Input data:  [batch, in_height, in_width, in_channels]
        # Kernel size: [fh, fw, kin_ch, kout_ch]
        return -1, -1, -1, self.kernel.shape[3]

    def cast(self, new_dtype: np.dtype):
        self.dtype = new_dtype
        self.kernel = self.kernel.astype(dtype=new_dtype)
        self.b = self.b.astype(dtype=new_dtype)

    def __copy__(self):
        c = Conv2dLayer(in_channels=self.in_channels,
                        out_channels=self.out_channels,
                        kernel_size=self.kernel_size,
                        activation=self.activation,
                        dtype=self.dtype,
                        kernel_init_weights=self.kernel.copy(),
                        bias_init_weights=self.b.copy())
        return c

    def quantize_layer(self, target_type, fraction_bits, zero_point):
        self.dtype = target_type
        self.kernel = quant.quantize_vector(self.kernel, target_type=target_type, max_value=max_value,
                                            min_value=min_value)
        self.b = quant.quantize_vector(self.b, target_type=target_type, max_value=max_value, min_value=min_value)


class ActivationLayer(Layer):

    # act_func: (np.ndarray) : np.ndarray

    def __init__(self, func):
        self.act_func = func

    def __call__(self, *args, **kwargs):
        x = args[0]
        return self.act_func(x)

    def get_output_shape(self, input_data_shape: np.ndarray = None):
        return input_data_shape.shape

    def get_input_shape(self):
        # accepts every shape
        pass


class ReluActivationLayer(ActivationLayer):

    def __init__(self):
        ActivationLayer.__init__(self, func=core.relu)


class SoftmaxLayer(ActivationLayer):

    def __init__(self):
        ActivationLayer.__init__(self, func=core.softmax)


class ReshapeLayer(Layer):
    newshape: np.ndarray

    def __init__(self, newshape):
        self.newshape = newshape

    def __call__(self, *args, **kwargs):
        x = args[0]
        return reshape(x, newshape=self.newshape)

    def get_input_shape(self):
        pass  # can be anything

    def get_output_shape(self, input_data_shape: np.ndarray = None):
        return self.newshape


class QConv(Conv2dLayer):

    def __init__(self,
                 in_channels,
                 out_channels,
                 kernel_size,
                 activation,
                 kernel_weights,
                 kernel_scaling,
                 bias_weights,
                 bias_scaling,
                 weight_dtype=np.int8,
                 activations_dtype=np.int8,
                 ):
        super(QConv, self).__init__(in_channels=in_channels, out_channels=out_channels, kernel_size=kernel_size,
                                    activation=activation)
        self.kernel = kernel_weights
        self.bias = bias_weights

        self.kernel_scaling = kernel_scaling
        self.bias_scaling = bias_scaling

    def __call__(self, *args, **kwargs):
        super.__call__(*args, **kwargs)


class QuantFullyConnected(FullyConnectedLayer):

    def __init__(self,
                 input_size,
                 output_size,
                 input_activation_dtype=np.int8,
                 input_activation_frac_bits=7,
                 output_activation_dtype=np.int8,
                 output_activation_frac_bits=7,
                 activation=None,
                 dtype=np.float32,
                 weights=None,
                 bias=None,
                 weight_quant_dtype=np.int8,
                 bias_quant_dtype=np.int8,
                 weight_quant_frac_bits=7,
                 bias_quant_frac_bits=7):
        super().__init__(input_size, output_size, activation, dtype, weights, bias)

        self.input_activation_dtype = input_activation_dtype
        self.input_activation_frac_bits = input_activation_frac_bits
        self.output_activation_dtype = output_activation_dtype
        self.output_activation_frac_bits = output_activation_frac_bits

        self.weight_quant_dtype = weight_quant_dtype
        self.bias_quant_dtype = bias_quant_dtype
        self.weight_quant_frac_bits = weight_quant_frac_bits
        self.bias_quant_frac_bits = bias_quant_frac_bits

        # Check if weights are float
        if weights.dtype in [np.float, np.float64, np.float16, np.float32]:
            self.weights = quant.to_fpi(weights, fraction_bits=weight_quant_frac_bits, target_type=weight_quant_dtype)
            self.bias = quant.to_fpi(bias, fraction_bits=weight_quant_frac_bits, target_type=weight_quant_dtype)


class QuantConv2dLayer(Conv2dLayer):
    pass